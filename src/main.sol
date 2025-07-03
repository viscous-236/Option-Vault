// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DataTypes} from "./library/DataTypes.sol";
import {ValidationLogic} from "./library/ValidationLogic.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OptionLogic} from "./library/OptionLogic.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPERMIT2} from "./interfaces/IPERMIT2.sol";
import {Permit2Logic} from "./library/Permit2Logic.sol";
import {AaveInteraction} from "./library/AaveInteraction.sol";
import {AutomationCompatibleInterface} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {AutomationLogic} from "./library/AutomationLogic.sol";

contract Main is ReentrancyGuard, AutomationCompatibleInterface {
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
    error Main__UserAlreadyPayedThePremium(uint256 optionId, address user);
    error Main__AmountExceedsOptionAmount(uint256 optionId, uint256 amount, uint256 optionAmount);

    using ValidationLogic for DataTypes.OptionData;

    uint256[] public activeOptionIds;
    mapping(uint256 => uint256) private optionIdIndex;
    uint256 public nextOptionId;
    uint256 public lastCheckedIndex;
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
    event OptionSettled(uint256 indexed optionId);

    function createOption(bool _isCall, uint256 amount, uint256 strikePrice, uint256 dueDate) external {
        DataTypes.OptionData memory optionData =
            OptionLogic.createOption(strikePrice, amount, _isCall, msg.sender, dueDate);

        // Set collateral and buyer token addresses based on option type
        (optionData.collateralAddress, optionData.buyerTokenAddress) =
            _isCall ? (i_wETHAddress, i_usdcAddress) : (i_usdcAddress, i_wETHAddress);

        optionData.validateOptionData();

        uint256 optionId = nextOptionId++;
        options[optionId] = optionData;
        optionIdIndex[optionId] = activeOptionIds.length;
        activeOptionIds.push(optionId);
        isIdExists[optionId] = true;

        emit OptionCreated(optionId, optionData);
    }

    function depositCollateralToAave(uint256 optionId) external nonReentrant {
        if (!isIdExists[optionId]) {
            revert Main__OptionIdDoesNotExist(optionId);
        }

        DataTypes.OptionData storage optionData = options[optionId];
        optionData.validateCollateralPayment();

        if (!AaveInteraction.depositCollateralToAave(optionData, optionData.amount, address(this))) {
            revert Main__CollateralDepositToAaveFailed(
                optionId, optionData.collateralAddress, msg.sender, optionData.amount
            );
        }

        emit CollaterlDeposited(optionId, optionData.collateralAddress, msg.sender, optionData.amount);
    }

    function payPremiumWithPermit2(uint256 optionId, uint256 nounce, bytes calldata signature) external nonReentrant {
        DataTypes.OptionData storage optionData = options[optionId];
        optionData.validateOptionData();
        optionData.validatePremiumPay();

        if (isEligibleForExercise[optionId][msg.sender]) {
            revert Main__UserAlreadyPayedThePremium(optionId, msg.sender);
        }

        // Process premium payment
        _processPremiumPayment(optionId, optionData, nounce, signature);
    }

    function exerciseOption(uint256 optionId, uint256 nonce, bytes calldata signature, uint256 amount)
        external
        nonReentrant
    {
        DataTypes.OptionData storage optionData = options[optionId];
        optionData.validateExerciseOption(optionId, amount, msg.sender);

        if (!isEligibleForExercise[optionId][msg.sender]) {
            revert Main__UserIsNotEligibleForExercise(optionId, msg.sender);
        }

        _validateCollateralAvailability(optionId, optionData, amount);
        _processExercisePayment(optionId, optionData, nonce, signature, amount);
        _withdrawAndTransferCollateral(optionId, optionData, amount);

        emit CollateralWithdrawed(optionId, amount);
    }

    function _processPremiumPayment(
        uint256 optionId,
        DataTypes.OptionData storage optionData,
        uint256 nounce,
        bytes calldata signature
    ) internal {
        optionData.eligibleBuyers.push(msg.sender);
        isEligibleForExercise[optionId][msg.sender] = true;
        premiumCollected[optionId] += optionData.premium;

        if (
            !Permit2Logic.transferUsingPermit2(
                optionData.premium, nounce, signature, optionData.buyerTokenAddress, address(this)
            )
        ) {
            revert Main__PremiumPaymentFailed(optionId, optionData.buyerTokenAddress, msg.sender, optionData.premium);
        }

        if (!optionData.isEligibleForExercise) {
            optionData.isEligibleForExercise = true;
        }

        emit PremiumPaid(optionId, optionData.buyerTokenAddress, msg.sender, optionData.premium);
    }

    function _validateCollateralAvailability(uint256 optionId, DataTypes.OptionData storage optionData, uint256 amount)
        internal
        view
    {
        address aTokenAddress = AaveInteraction.getCollateralATokenAddress(optionData);
        uint256 aTokenAmount = IERC20(aTokenAddress).balanceOf(address(this));

        if (aTokenAmount < amount) {
            revert Main__LessCollateralThanRequired(optionId, aTokenAmount, amount);
        }
    }

    function _processExercisePayment(
        uint256 optionId,
        DataTypes.OptionData storage optionData,
        uint256 nonce,
        bytes calldata signature,
        uint256 amount
    ) internal {
        uint256 paymentAmount = optionData.isCall ? amount * optionData.strikePrice : amount;

        if (
            !Permit2Logic.transferUsingPermit2(
                paymentAmount, nonce, signature, optionData.buyerTokenAddress, optionData.writerAddress
            )
        ) {
            revert Main__PremiumPaymentFailed(optionId, optionData.buyerTokenAddress, msg.sender, paymentAmount);
        }
    }

    function _withdrawAndTransferCollateral(uint256 optionId, DataTypes.OptionData storage optionData, uint256 amount)
        internal
    {
        uint256 withdrawAmount = AaveInteraction.withdrawCollateralFromAave(optionData, amount, msg.sender);
        collateralWithdrawed[optionId] += withdrawAmount;

        if (collateralWithdrawed[optionId] >= optionData.amount) {
            optionData.isEligibleForExercise = false;
        }
    }

    /**
     * @dev Chainlink Automation checkUpkeep function
     * @return upkeepNeeded Whether upkeep is needed
     * @return performData Encoded data for performUpkeep
     */
    function checkUpkeep(bytes calldata /* checkData */ )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        return AutomationLogic.checkUpkeepNeeded(activeOptionIds, options, lastCheckedIndex);
    }

    /**
     * @dev Chainlink Automation performUpkeep function
     * @param performData Encoded data from checkUpkeep containing optionId and nextIndex
     */
    function performUpkeep(bytes calldata performData) external override {
        (uint256 newIndex, bool settled) = AutomationLogic.performSingleOptionUpkeep(
            activeOptionIds, options, collateralWithdrawed, performData, address(this)
        );

        lastCheckedIndex = newIndex;

        if (settled) {
            (uint256 optionId,) = abi.decode(performData, (uint256, uint256));
            emit OptionSettled(optionId);
            _removeActiveOption(optionId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                     INTERNAL_AND_PRIVATE_FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _removeActiveOption(uint256 optionId) internal {
        uint256 index = optionIdIndex[optionId];
        uint256 lastIndex = activeOptionIds.length - 1;
        uint256 lastId = activeOptionIds[lastIndex];

        activeOptionIds[index] = lastId;
        optionIdIndex[lastId] = index;

        activeOptionIds.pop();
        delete optionIdIndex[optionId];
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER_FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getCollateralAmount(uint256 optionId) external view returns (uint256) {
        if (!isIdExists[optionId]) {
            revert Main__OptionIdDoesNotExist(optionId);
        }
        return options[optionId].amount;
    }

    function getAllActiveOptionIds() external view returns (uint256[] memory) {
        return activeOptionIds;
    }
}
