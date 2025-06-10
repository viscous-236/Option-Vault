//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DataTypes} from "../library/DataTypes.sol";
import {ValidationLogic} from "../library/ValidationLogic.sol";
import {PaymentLogic} from "../library/PaymentLogic.sol";

library ExcersciseLogic {
    using ValidationLogic for DataTypes.OptionData;

    function payPremium(DataTypes.OptionData storage optionData) internal {
        optionData.validateOptionData();
        if (optionData.premium <= 0) {
            revert ValidationLogic.ValidationLogic__MustBeGreaterThanZero(optionData.premium);
        }

        // send the premium to the pool
    }

    function exerciseOption(DataTypes.OptionData storage optionData, address buyer) internal {
        optionData.validateExercise();

        optionData.buyerAddress = buyer;
        optionData.isExercised = true;
    }
}
