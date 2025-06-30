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
    error Main__CollateralDepositToAaveFailed(
        uint256 optionId, address collateralAddress, address depositor, uint256 amount
    );
    error Main__CollateralWithdrawFailed(uint256 optionId, uint256 amount);
    error Main__OptionIdDoesNotExist(uint256 optionId);
    error Main__UserIsNotEligibleForExercise(uint256 optionId, address user);
    error Main__LessCollateralThanRequired(uint256 optionId, uint256 aTokenAmount, uint256 requiredAmount);
    error Main__CollateralPaymentToExerciserFalied(
        uint256 optionId, address collateralAddress, address exerciser, uint256 amount
    );

    using ValidationLogic for DataTypes.OptionData;

    uint256 private optionIdCounter;
    address private immutable i_usdcAddress;
    address private immutable i_wETHAddress;
    mapping(uint256 => DataTypes.OptionData) public options;
    mapping(uint256 => bool) private isIdExists;
    mapping(uint256 id => mapping(address buyerAddress => bool isEligible)) public isEligibleForExercise;
    mapping(uint256 id => uint256 premiumCollected) public premiumCollected;
    mapping(uint256 id => uint256 collateralWithdrawed) public collateralWithdrawed;

    constructor(address _usdcAddress, address _wETHAddress) {
        i_usdcAddress = _usdcAddress;
        i_wETHAddress = _wETHAddress;
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
        bool success = AaveInteraction.depositCollateralToAave(optionData, collateralAmount, address(this));
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

        if (isEligibleForExercise[optionId][msg.sender]) {
            revert Main__UserAlreadyPayedThePremium(optionId, msg.sender);
        }

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

        if (!optionData.isEligibleForExercise) {
            optionData.isEligibleForExercise = true;
        }

        emit PremiumPaid(optionId, token, msg.sender, premiumAmount);
    }

    function exerciseOption(uint256 optionId, uint256 nonce, bytes calldata signature, uint256 amount)
        external
        nonReentrant
    {
        DataTypes.OptionData storage optionData = options[optionId];
        optionData.validateExerciseOption();
        if (!isEligibleForExercise[optionId][msg.sender]) {
            revert Main__UserIsNotEligibleForExercise(optionId, msg.sender);
        }
        if (amount > optionData.amount) {
            revert ValidationLogic.ValidationLogic__MustBeGreaterThanZero(optionData.amount);
        }

        collateralWithdrawed[optionId] += amount;
        if (collateralWithdrawed[optionId] >= optionData.amount) {
            optionData.isEligibleForExercise = false;
        }

        bool success;
        if (optionData.isCall) {
            success = Permit2Logic.transferUsingPermit2(
                amount, nonce, signature, optionData.buyerTokenAddress, optionData.writerAddress
            );
        } else {
            success = Permit2Logic.transferUsingPermit2(
                amount, nonce, signature, optionData.buyerTokenAddress, optionData.writerAddress
            );
        }

        if (success) {
            // Check aToken balance
            address aTokenAddress = AaveInteraction.getReserveData(optionData.collateralAddress).aTokenAddress;
            IERC20 aToken = IERC20(aTokenAddress);
            uint256 aTokenAmount = aToken.balanceOf(address(this));

            if (aTokenAmount < amount) {
                collateralWithdrawed[optionId] -= amount;
                if (collateralWithdrawed[optionId] < optionData.amount) {
                    optionData.isEligibleForExercise = true;
                }
                revert Main__LessCollateralThanRequired(optionId, aTokenAmount, amount);
            }

            uint256 withdrawAmount = AaveInteraction.withdrawCollateralFromAave(optionData, amount, address(this));
            if (withdrawAmount < amount) {
                collateralWithdrawed[optionId] -= amount;
                if (collateralWithdrawed[optionId] < optionData.amount) {
                    optionData.isEligibleForExercise = true;
                }
                revert Main__CollateralWithdrawFailed(optionId, amount);
            }

            IERC20 collateralToken = IERC20(optionData.collateralAddress);
            bool transferSuccess = collateralToken.transfer(msg.sender, amount);
            if (!transferSuccess) {
                collateralWithdrawed[optionId] -= amount;
                if (collateralWithdrawed[optionId] < optionData.amount) {
                    optionData.isEligibleForExercise = true;
                }
                revert Main__CollateralPaymentToExerciserFalied(
                    optionId, optionData.collateralAddress, msg.sender, amount
                );
            }
        }

        emit CollateralWithdrawed(optionId, amount);
    }

    /*//////////////////////////////////////////////////////////////
                     INTERNAL_AND_PRIVATE_FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getCollateralAmount(uint256 optionId) external view returns (uint256) {
        if (!isIdExists[optionId]) {
            revert Main__OptionIdDoesNotExist(optionId);
        }
        DataTypes.OptionData storage optionData = options[optionId];
        return optionData.amount;
    }
}
