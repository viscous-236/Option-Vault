// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DataTypes} from "../library/DataTypes.sol";
import {ValidationLogic} from "../library/ValidationLogic.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "aave-v3-origin/src/contracts/interfaces/IPool.sol";

library AaveInteraction {
    using ValidationLogic for DataTypes.OptionData;

    IPool private constant AAVE_POOL = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    function depositCollateralToAave(DataTypes.OptionData storage optionData, uint256 _amount, address _depositer) internal returns (bool) {

        AAVE_POOL.supply(
            optionData.collateralAddress,
            _amount,
            _depositer,
            0
        );

        return true;
    }

    function withdrawCollateralFromAave(DataTypes.OptionData storage optionData) internal returns (bool,uint256) {
        IERC20 collateralToken = IERC20(optionData.collateralAddress);

        uint256 withdrawAmount = AAVE_POOL.withdraw(
            collateralToken,
            type(uint256).max,
            msg.sender
        );

        return (true,withdrawAmount);
    }

}
