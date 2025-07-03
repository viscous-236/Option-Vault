// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DataTypes} from "./DataTypes.sol";
import {AaveInteraction} from "./AaveInteraction.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library AutomationLogic {
    error AutomationLogic__NoExpiredOptions();
    error AutomationLogic__SettlementFailed(uint256 optionId);
    error AutomationLogic__InvalidOptionData(uint256 optionId);
    error AutomationLogic__OptionNotExpired(uint256 optionId);

    /**
     * @dev Finds the next expired option from activeOptionIds starting at given index
     * @param activeOptionIds Array of currently active option IDs
     * @param options Mapping of all options
     * @param startIndex Index to start searching from in activeOptionIds
     * @return found Whether an expired option was found
     * @return optionId The ID of the expired option (if found)
     * @return nextIndex Next index to check from (startIndex + 1)
     */
    function findNextExpiredOption(
        uint256[] storage activeOptionIds,
        mapping(uint256 => DataTypes.OptionData) storage options,
        uint256 startIndex
    ) internal view returns (bool found, uint256 optionId, uint256 nextIndex) {
        uint256 activeLength = activeOptionIds.length;

        for (uint256 i = startIndex; i < activeLength;) {
            uint256 currentOptionId = activeOptionIds[i];
            DataTypes.OptionData storage optionData = options[currentOptionId];

            // Check if option is expired and not eligible for exercise (ready for settlement)
            if (block.timestamp > optionData.dueDate && !optionData.isEligibleForExercise && !optionData.isSettled) {
                return (true, currentOptionId, i + 1);
            }

            unchecked {
                ++i;
            }
        }

        return (false, 0, activeLength);
    }

    /**
     * @dev Settles a single expired option by directly withdrawing to writer
     * @param options Mapping of all options
     * @param collateralWithdrawed Mapping of withdrawn amounts per option
     * @param optionId The option ID to settle
     * @param contractAddress Address of the main contract (for balance checking)
     * @return success Whether settlement was successful
     */
    function settleSingleOption(
        mapping(uint256 => DataTypes.OptionData) storage options,
        mapping(uint256 => uint256) storage collateralWithdrawed,
        uint256 optionId,
        address contractAddress
    ) internal returns (bool success) {
        DataTypes.OptionData storage optionData = options[optionId];

        // Validate option data
        if (optionData.writerAddress == address(0)) {
            revert AutomationLogic__InvalidOptionData(optionId);
        }

        // Check if option is actually expired
        if (block.timestamp <= optionData.dueDate) {
            revert AutomationLogic__OptionNotExpired(optionId);
        }

        // Check if already settled
        if (optionData.isSettled) {
            return true; // Already settled
        }

        // Calculate settlement amounts
        address aTokenAddress = AaveInteraction.getCollateralATokenAddress(optionData);
        uint256 currentATokenBalance = IERC20(aTokenAddress).balanceOf(contractAddress);

        uint256 remainingCollateral;
        unchecked {
            remainingCollateral = optionData.amount - collateralWithdrawed[optionId];
        }

        // Calculate yield earned (if any)
        uint256 yieldEarned;
        if (currentATokenBalance > remainingCollateral) {
            unchecked {
                yieldEarned = currentATokenBalance - remainingCollateral;
            }
        }

        uint256 totalToWithdraw;
        unchecked {
            totalToWithdraw = remainingCollateral + yieldEarned;
        }

        // Withdraw directly to writer if there's anything to withdraw
        if (totalToWithdraw > 0) {
            uint256 withdrawnAmount =
                AaveInteraction.withdrawCollateralFromAave(optionData, totalToWithdraw, optionData.writerAddress);

            // Adjust yield calculation based on actual withdrawal
            if (withdrawnAmount < totalToWithdraw) {
                if (withdrawnAmount <= remainingCollateral) {
                    yieldEarned = 0;
                } else {
                    unchecked {
                        yieldEarned = withdrawnAmount - remainingCollateral;
                    }
                }
            }
        }

        // Mark as settled and store yield earned
        optionData.isSettled = true;
        optionData.yeildEarned = yieldEarned;

        return true;
    }

    /**
     * @dev Checks if upkeep is needed by finding next expired option
     * @param activeOptionIds Array of active option IDs
     * @param options Mapping of all options
     * @param lastCheckedIndex Index of last checked option in activeOptionIds
     * @return upkeepNeeded Whether upkeep is needed
     * @return performData Encoded data for performUpkeep (optionId and nextIndex)
     */
    function checkUpkeepNeeded(
        uint256[] storage activeOptionIds,
        mapping(uint256 => DataTypes.OptionData) storage options,
        uint256 lastCheckedIndex
    ) internal view returns (bool upkeepNeeded, bytes memory performData) {
        (bool found, uint256 optionId, uint256 nextIndex) =
            findNextExpiredOption(activeOptionIds, options, lastCheckedIndex);

        if (found) {
            upkeepNeeded = true;
            performData = abi.encode(optionId, nextIndex);
        } else {
            upkeepNeeded = false;
            performData = abi.encode(0, 0); // Reset to start from beginning next time
        }
    }

    /**
     * @dev Performs upkeep by settling one expired option
     * @param activeOptionIds Array of active option IDs
     * @param options Mapping of all options
     * @param collateralWithdrawed Mapping of withdrawn amounts
     * @param performData Encoded data from checkUpkeep
     * @param contractAddress Address of the main contract
     * @return newLastCheckedIndex Updated index for next checkUpkeep
     * @return settled Whether an option was actually settled
     */
    function performSingleOptionUpkeep(
        uint256[] storage activeOptionIds,
        mapping(uint256 => DataTypes.OptionData) storage options,
        mapping(uint256 => uint256) storage collateralWithdrawed,
        bytes calldata performData,
        address contractAddress
    ) internal returns (uint256 newLastCheckedIndex, bool settled) {
        (uint256 optionId, uint256 nextIndex) = abi.decode(performData, (uint256, uint256));

        // If optionId is 0, reset and start from beginning
        if (optionId == 0) {
            return (0, false);
        }

        // Settle the specific option
        settled = settleSingleOption(options, collateralWithdrawed, optionId, contractAddress);

        // Return next index to check from
        newLastCheckedIndex = nextIndex >= activeOptionIds.length ? 0 : nextIndex;
    }

    /**
     * @dev Gets the yield earned for a settled option
     * @param options Mapping of all options
     * @param optionId The option ID
     * @return yieldEarned The yield earned amount
     */
    function getYieldEarned(mapping(uint256 => DataTypes.OptionData) storage options, uint256 optionId)
        internal
        view
        returns (uint256 yieldEarned)
    {
        return options[optionId].yeildEarned;
    }
}
