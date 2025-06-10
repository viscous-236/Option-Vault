// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DataTypes} from "./library/DataTypes.sol";
import {ValidationLogic} from "./library/ValidationLogic.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OptionLogic} from "./library/OptionLogic.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPERMIT2} from "./interfaces/IPERMIT2.sol";

contract Main is ERC20, ReentrancyGuard {
    using ValidationLogic for DataTypes.OptionData;

    uint256 private optionIdCounter;
    IERC20 private immutable usdcToken;
    IERC20 private immutable wETHToken;
    IPERMIT2 private constant PERMIT2 = IPERMIT2(0x000000000022D473030F116dDEE9F6B43aC78BA);
    address private immutable usdcAddress;
    address private immutable wETHAddress;
    mapping(uint256 => DataTypes.OptionData) public options;

    constructor(address _usdcAddress, address _wETHAddress) {
        usdcAddress = _usdcAddress;
        wETHAddress = _wETHAddress;
        usdcToken = IERC20(_usdcAddress);
        wETHToken = IERC20(_wETHAddress);
    }

    event OptionCreated(uint256 indexed optionId, DataTypes.OptionData optionData);

    function createOption(bool _isCall, uint256 amount, uint256 strikePrice, uint256 dueDate) external {
        DataTypes.OptionData memory optionData =
            OptionLogic.createOption(strikePrice, amount, _isCall, msg.sender, dueDate);

        if (_isCall) {
            optionData.collateralAddress = wETHAddress;
        } else {
            optionData.collateralAddress = usdcAddress;
        }

        optionData.validateOptionData();
        options[optionIdCounter] = optionData;
        optionIdCounter++;
        emit OptionCreated(optionIdCounter - 1, optionData);
    }

    function payCollateralWithPermit2(uint256 optionId, uint256 nounce, bytes calldata signature)
        external
        nonReentrant
    {
        DataTypes.OptionData storage optionData = options[optionId];
        optionData.validateOptionData();
        optionData.validateCollateralPayment(optionData);

        uint256 collateralAmount = optionData.amount;

        PERMIT2.permitTransferFrom(
            IPERMIT2.PermitTransferFrom({
                permitted: IPERMIT2.TokenPermissions({token: optionData.collateralAddress, amount: collateralAmount}),
                nonce: nounce,
                deadline: block.timestamp + 1 days
            }),
            IPERMIT2.SignatureTransferDetails({to: address(this), requestedAmount: collateralAmount}),
            msg.sender,
            signature
        );

        emit CollateraPayed(optionId, optionData.collateralAddress, msg.sender, collateralAmount);
    }
}
