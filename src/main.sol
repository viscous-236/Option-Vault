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

abstract contract Main is ERC20, ReentrancyGuard {
    error Main__CollateralPaymentFailed(uint256 optionId, address collateralAddress, address payer, uint256 amount);
    error Main__PremiumPaymentFailed(uint256 optionId, address token, address payer, uint256 amount);
    error Main__CollateralDepositToAaveFailed(uint256 optionId, address collateralAddress, address depositor, uint256 amount);
    error Main__CollateralWithdrawFailed(uint256 optionId);
    error Main__OptionIdDoesNotExist(uint256 optionId);
    error Main__UserIsNotEligibleForExercise(uint256 optionId, address user);

    using ValidationLogic for DataTypes.OptionData;

    uint256 private optionIdCounter;
    IERC20 private immutable usdcToken;
    IERC20 private immutable wETHToken;
    address private immutable usdcAddress;
    address private immutable wETHAddress;
    mapping(uint256 => DataTypes.OptionData) public options;
    mapping(uint256 => bool) private isIdExists;
    mapping(uint256 id => mapping(address buyerAddress => bool isEligible)) public isEligibleForExercise;
    mapping(uint256 id => uint256 premiumCollected) public premiumCollected;

    constructor(address _usdcAddress, address _wETHAddress) {
        usdcAddress = _usdcAddress;
        wETHAddress = _wETHAddress;
        usdcToken = IERC20(_usdcAddress);
        wETHToken = IERC20(_wETHAddress);
    }

    event OptionCreated(uint256 indexed optionId, DataTypes.OptionData optionData);
    event CollateraPayed(uint256 indexed optionId, address collateralAddress, address payer, uint256 amount);
    event PremiumPaid(uint256 indexed optionId, address token, address payer, uint256 amount);
    event CollaterlDeposited(uint256 indexed optionId, address collateralAddress, address depositor, uint256 amount);
    event CollateralWithdrawed(uint256 indexed optionId, uint256 amountWithdrawed);


    function createOption(bool _isCall, uint256 amount, uint256 strikePrice, uint256 dueDate) external {
        DataTypes.OptionData memory optionData =
            OptionLogic.createOption(strikePrice, amount, _isCall, msg.sender, dueDate);

        if (_isCall) {
            optionData.collateralAddress = wETHAddress;
            optionData.buyerTokenAddress = usdcAddress;
        } else {
            optionData.collateralAddress = usdcAddress;
            optionData.buyerTokenAddress = wETHAddress;
        }

        optionData.validateOptionData();
        options[optionIdCounter] = optionData;
        isIdExists[optionIdCounter] = true;
        optionIdCounter++;
        emit OptionCreated(optionIdCounter - 1, optionData);
    }

    


    function depositCollateralToAave(uint256 optionId) external nonReentrant returns (bool) {
        if (!isIdExists[optionId]) {
            revert Main__OptionIdDoesNotExist(optionId);
        }
        DataTypes.OptionData storage optionData = options[optionId];
        optionData.validateCollateralPayment();

        uint256 collateralAmount = optionData.amount;
        bool success = AaveInteraction.depositCollateralToAave(optionData, collateralAmount, msg.sender);
        if (!success) {
            revert Main__CollateralDepositToAaveFailed(
                optionId, optionData.collateralAddress, msg.sender, collateralAmount
            );
        }

        emit CollaterlDeposited(optionId, optionData.collateralAddress, msg.sender, collateralAmount);
    }

    function payPremiumWithPermit2(uint256 optionId, uint256 nounce, bytes calldata signature) external nonReentrant {
        DataTypes.OptionData storage optionData = options[optionId];
        optionData.validateOptionData();
        optionData.validatePremiumPay();

        address token;
        if (optionData.isCall) {
            token = usdcAddress;
        } else {
            token = wETHAddress;
        }

        optionData.eligibleBuyers.push(msg.sender);
        isEligibleForExercise[optionId][msg.sender] = true;
        premiumCollected[optionId] += optionData.premium;

        uint256 premiumAmount = optionData.premium;
        bool success = Permit2Logic.transferUsingPermit2(premiumAmount, nounce, signature, token, address(this));

        if (!success) {
            revert Main__PremiumPaymentFailed(optionId, token, msg.sender, premiumAmount);
        }

        if (!optionData.isEligibleForExercise)
        {
            optionData.isEligibleForExercise = true;
        }

        emit PremiumPaid(optionId, token, msg.sender, premiumAmount);
    }

    function exerciseOption(uint256 optionId, uint256 nounce, bytes calldata signature) external nonReentrant {
        DataTypes.OptionData storage optionData = options[optionId];
        optionData.validateExerciseOption();
        if (!isEligibleForExercise[optionId][msg.sender]) {
            revert Main__UserIsNotEligibleForExercise(optionId, msg.sender);
        }

        bool success;
        if (optionData.isCall) {
            success = Permit2Logic.transferUsingPermit2(
                optionData.amount, nounce, signature, optionData.buyerTokenAddress, optionData.writerAddress);
        }else {
            success = Permit2Logic.transferUsingPermit2(
                optionData.amount, nounce, signature, optionData.buyerTokenAddress, optionData.writerAddress);
        }
    }


    /*//////////////////////////////////////////////////////////////
                     INTERNAL_AND_PRIVATE_FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _withdrawCollateralFromAave(uint256 optionId) internal returns (bool) {
        DataTypes.OptionData storage optionData = options[optionId];
        optionData.validateCollateralPayment();

        (bool success, uint256 amountWithdrawed) = AaveInteraction.withdrawCollateralFromAave(optionData);
        if (!success) {
            revert Main__CollateralWithdrawFailed(optionId);
        }

        optionData.yeildEarned = optionData.amount - amountWithdrawed;

        emit CollateralWithdrawed(optionId,amountWithdrawed);
    }
        

}
