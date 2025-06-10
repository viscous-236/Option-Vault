// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// Importing libraries
import {DataTypes} from "./library/DataTypes.sol";
import {ValidationLogic} from "./library/ValidationLogic.sol";

contract Main {
    using ValidationLogic for DataTypes.OptionData;

    uint256 private optionIdCounter;
    mapping(uint256 => DataTypes.OptionData) public options;
    mapping(DataTypes.OptionData => uint256) public totalPremiumCollected;
}
