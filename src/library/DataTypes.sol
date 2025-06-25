// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

library DataTypes {
    struct OptionData {
        address writerAddress;
        bool isCall;
        address collateralAddress;
        address buyerTokenAddress;
        uint256 amount;
        uint256 premium;
        uint256 strikePrice;
        uint256 dueDate;
        uint256 createdAt;
        address buyerAddress;
        bool isEligibleForExercise;
        address[] eligibleBuyers;
        bool isExercised;
        bool isSettled;
        uint256 yeildEarned;
    }
}
