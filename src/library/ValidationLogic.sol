//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DataTypes} from "./DataTypes.sol";

library ValidationLogic {
    error ValidationLogic__MustBeGreaterThanZero(uint256 value);
    error ValidationLogic__DueDateMustBeInFuture();
    error ValidationLogic__DueDateAlreadyPassed();
    error ValidationLogic__CollateralAddressCannotBeZero();
    error ValidationLogic__BuyerAddressCannotBeZero();
    error ValidationLogic__WriterAddressCannotBeZero();
    error ValidationLogic__OptionIsAlreadyExerscised();
    error ValidationLogic__OptionIsAlreadySettled();
    error ValidationLogic__OptionIsNotEligibleForExercise();

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
        if (block.timestamp > optionData.dueDate) {
            revert ValidationLogic__DueDateAlreadyPassed();
        }
        if (optionData.collateralAddress == address(0)) {
            revert ValidationLogic__CollateralAddressCannotBeZero();
        }

        return true;
    }

    function validateExercise(DataTypes.OptionData memory optionData) internal view returns (bool) {
        if (optionData.isExercised) {
            revert ValidationLogic__OptionIsAlreadyExerscised();
        }
        if (optionData.isSettled) {
            revert ValidationLogic__OptionIsAlreadySettled();
        }
        if (block.timestamp > optionData.dueDate) {
            revert ValidationLogic__DueDateAlreadyPassed();
        }
        if (optionData.buyerAddress == address(0)) {
            revert ValidationLogic__BuyerAddressCannotBeZero();
        }
        if (optionData.writerAddress == address(0)) {
            revert ValidationLogic__WriterAddressCannotBeZero();
        }
        if (!optionData.isEligibleForExercise) {
            revert ValidationLogic__OptionIsNotEligibleForExercise();
        }

        return true;
    }

    function validateCollateralPayment(
        DataTypes.OptionData memory optionData
    ) internal pure returns (bool) {
        if (optionData.collateralAddress == address(0)) {
            revert ValidationLogic__CollateralAddressCannotBeZero();
        }
        if (optionData.writerAddress == address(0)) {
            revert ValidationLogic__WriterAddressCannotBeZero();
        }

        return true;
}
