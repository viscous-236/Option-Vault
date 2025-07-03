//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DataTypes} from "./DataTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library ValidationLogic {
    error ValidationLogic__MustBeGreaterThanZero(uint256 value);
    error ValidationLogic__DueDateMustBeInFuture();
    error ValidationLogic__DueDateAlreadyPassed();
    error ValidationLogic__CollateralAddressCannotBeZero();
    error ValidationLogic__BuyerAddressCannotBeZero();
    error ValidationLogic__WriterAddressCannotBeZero();
    error ValidationLogic__OptionIsAlreadySettled();
    error ValidationLogic__OptionIsNotEligibleForExercise();
    error ValidationLogic__AmountExceedsOptionAmount(uint256 amount);
    error ValidationLogic__BuyerDosentHaveEnoughAmount(
        uint256 optionId, address buyerTokenAddress, address buyer, uint256 requiredAmount
    );

    function validateOptionData(DataTypes.OptionData memory optionData) internal view returns (bool) {
        if (optionData.amount <= 0) {
            revert ValidationLogic__MustBeGreaterThanZero(optionData.amount);
        }
        if (optionData.premium <= 0) {
            revert ValidationLogic__MustBeGreaterThanZero(optionData.premium);
        }
        if (optionData.strikePrice <= 0) {
            revert ValidationLogic__MustBeGreaterThanZero(optionData.strikePrice);
        }
        if (optionData.dueDate <= block.timestamp) {
            revert ValidationLogic__DueDateMustBeInFuture();
        }
        if (optionData.collateralAddress == address(0)) {
            revert ValidationLogic__CollateralAddressCannotBeZero();
        }
        if (optionData.writerAddress == address(0)) {
            revert ValidationLogic__WriterAddressCannotBeZero();
        }

        return true;
    }

    function validatePremiumPay(DataTypes.OptionData memory optionData) internal view returns (bool) {
        if (optionData.isSettled) {
            revert ValidationLogic__OptionIsAlreadySettled();
        }
        if (block.timestamp > optionData.dueDate) {
            revert ValidationLogic__DueDateAlreadyPassed();
        }
        if (optionData.writerAddress == address(0)) {
            revert ValidationLogic__WriterAddressCannotBeZero();
        }

        return true;
    }

    function validateCollateralPayment(DataTypes.OptionData memory optionData) internal pure returns (bool) {
        if (optionData.collateralAddress == address(0)) {
            revert ValidationLogic__CollateralAddressCannotBeZero();
        }
        if (optionData.writerAddress == address(0)) {
            revert ValidationLogic__WriterAddressCannotBeZero();
        }

        return true;
    }

    function validateExerciseOption(
        DataTypes.OptionData memory optionData,
        uint256 optionId,
        uint256 _amount,
        address _buyer
    ) internal view {
        uint256 strikeprice = optionData.strikePrice;
        uint256 amount = optionData.amount;
        if (!optionData.isEligibleForExercise) {
            revert ValidationLogic__OptionIsNotEligibleForExercise();
        }
        if (optionData.isSettled) {
            revert ValidationLogic__OptionIsAlreadySettled();
        }
        if (block.timestamp > optionData.dueDate) {
            revert ValidationLogic__DueDateAlreadyPassed();
        }
        if (_amount > amount) {
            revert ValidationLogic__AmountExceedsOptionAmount(_amount);
        }
        if (optionData.isCall) {
            if (IERC20(optionData.buyerTokenAddress).balanceOf(_buyer) < amount * strikeprice) {
                revert ValidationLogic__BuyerDosentHaveEnoughAmount(
                    optionId, optionData.buyerTokenAddress, _buyer, amount * strikeprice
                );
            }
        } else {
            if (IERC20(optionData.buyerTokenAddress).balanceOf(_buyer) < amount) {
                revert ValidationLogic__BuyerDosentHaveEnoughAmount(
                    optionId, optionData.buyerTokenAddress, _buyer, amount
                );
            }
        }
    }
}
