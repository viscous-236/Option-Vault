// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DataTypes} from "./library/DataTypes.sol";
import {ValidationLogic} from "./library/ValidationLogic.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OptionLogic} from "./library/OptionLogic.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPERMIT2} from "./interfaces/IPERMIT2.sol";
import {Permit2Logic} from "./library/Permit2Logic.sol";
import {AaveInteraction} from "./library/AaveInteraction.sol";

contract Main is ERC20, ReentrancyGuard {
    error Main__CollateralPaymentFailed(uint256 optionId, address collateralAddress, address payer, uint256 amount);
    error Main__PremiumPaymentFailed(uint256 optionId, address token, address payer, uint256 amount);

    using ValidationLogic for DataTypes.OptionData;

    uint256 private optionIdCounter;
    IERC20 private immutable usdcToken;
    IERC20 private immutable wETHToken;
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
    event CollateraPayed(uint256 indexed optionId, address collateralAddress, address payer, uint256 amount);
    event PremiumPaid(uint256 indexed optionId, address token, address payer, uint256 amount);

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

        bool success = Permit2Logic.transferUsingPermit2(
            collateralAmount, nounce, signature, optionData.collateralAddress, address(this)
        );

        if (!success) {
            revert Main__CollateralPaymentFailed(optionId, optionData.collateralAddress, msg.sender, collateralAmount);
        }

        depositCollateralToAave(optionId);

        emit CollateraPayed(optionId, optionData.collateralAddress, msg.sender, collateralAmount);
    }

    

    function payPremiumWithPermit2(uint256 optionId, uint256 nounce, bytes calldata signature) external nonReentrant {
        DataTypes.OptionData storage optionData = options[optionId];
        optionData.validateOptionData();

        address token;
        if (optionData.isCall) {
            token = usdcAddress;
        } else {
            token = wETHAddress;
        }

        optionData.eligibleBuyers.push(msg.sender);

        uint256 premiumAmount = optionData.premium;
        bool success = Permit2Logic.transferUsingPermit2(premiumAmount, nounce, signature, token, address(this));

        if (!success) {
            revert Main__PremiumPaymentFailed(optionId, token, msg.sender, premiumAmount);
        }

        emit PremiumPaid(optionId, token, msg.sender, premiumAmount);
    }

    /*//////////////////////////////////////////////////////////////
                     INTERNAL_AND_PRIVATE_FUNCTIONS
    //////////////////////////////////////////////////////////////*/


    function depositCollateralToAave(uint256 optionId) internal nonReentrant returns (bool) {
        DataTypes.OptionData storage optionData = options[optionId];
        optionData.validateOptionData();
        optionData.validateCollateralPayment(optionData);

        uint256 collateralAmount = optionData.amount;
        bool success = AaveInteraction.depositCollateralToAave(optionData, collateralAmount);
        if (!success) {
            revert Main__CollateralDepositToAaveFailed(
                optionId, optionData.collateralAddress, msg.sender, collateralAmount
            );
        }

        emit CollaterlDepsited(optionId, optionData.collateralAddress, msg.sender, collateralAmount);


    }
}
