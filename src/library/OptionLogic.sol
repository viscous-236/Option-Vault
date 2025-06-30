//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DataTypes} from "../library/DataTypes.sol";
import {ValidationLogic} from "../library/ValidationLogic.sol";

library OptionLogic {
    using ValidationLogic for DataTypes.OptionData;

    uint256 constant PREMIUM_BASIS_POINTS = 500; // 5%
    uint256 constant BASIS_POINTS_DENOMINATOR = 10000;
    uint256 constant PRECISION_SCALE = 1e18;

    function createOption(uint256 strikePrice, uint256 amount, bool isCall, address writer, uint256 dueDate)
        internal
        view
        returns (DataTypes.OptionData memory)
    {
        DataTypes.OptionData memory optionData;

        uint256 collateralAmount = calculateCollateral(isCall, strikePrice, amount);

        uint256 premium = calculatePremium(isCall, strikePrice, amount);

        optionData.writerAddress = writer;
        optionData.isCall = isCall;
        optionData.collateralAddress = address(0);
        optionData.amount = collateralAmount;
        optionData.premium = premium;
        optionData.strikePrice = strikePrice;
        optionData.dueDate = dueDate;
        optionData.createdAt = block.timestamp;
        optionData.buyerAddress = address(0);
        optionData.isEligibleForExercise = false;
        optionData.eligibleBuyers = new address[](0);
        optionData.isSettled = false;
        optionData.yeildEarned = 0;

        optionData.validateOptionData();

        return optionData;
    }

    function calculateCollateral(bool isCall, uint256 strikePrice, uint256 amount)
        internal
        pure
        returns (uint256 finalcollateralAmount)
    {
        if (amount <= 0) {
            revert ValidationLogic.ValidationLogic__MustBeGreaterThanZero(amount);
        }
        if (strikePrice <= 0) {
            revert ValidationLogic.ValidationLogic__MustBeGreaterThanZero(strikePrice);
        }
        if (isCall) {
            finalcollateralAmount = amount;
        } else {
            finalcollateralAmount = (strikePrice * amount) / 1e18;
        }

        return finalcollateralAmount;
    }

    function calculatePremium(bool isCall, uint256 strikePrice, uint256 amount)
        internal
        pure
        returns (uint256 premium)
    {
        if (amount <= 0) {
            revert ValidationLogic.ValidationLogic__MustBeGreaterThanZero(amount);
        }
        if (strikePrice <= 0) {
            revert ValidationLogic.ValidationLogic__MustBeGreaterThanZero(strikePrice);
        }

        if (isCall) {
            premium = (strikePrice * amount * PREMIUM_BASIS_POINTS) / (BASIS_POINTS_DENOMINATOR * PRECISION_SCALE);
        } else {
            premium = (amount * PREMIUM_BASIS_POINTS) / BASIS_POINTS_DENOMINATOR;
        }

        if (premium == 0) {
            premium = 1;
        }

        return premium;
    }
}
