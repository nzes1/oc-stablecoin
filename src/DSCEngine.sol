// SPDX-License-Identifier: MIT

/*//////////////////////////////////////////////////////////////
                            CONTRACT LAYOUT
//////////////////////////////////////////////////////////////*/

/**
 * @dev Contract Layout based on RareSkills Solidity Style guide
 * here: https://www.rareskills.io/post/solidity-style-guide which expounds on
 * Solidity's recommended guide on the docs.
 * Type Declarations
 * State Variables
 * Events
 * Errors
 * Modifiers
 * Constructor
 * receive
 * fallback
 * Functions:
 *  External
 *      External View
 *      External pure
 *  Public
 *      Public View
 *      Public pure
 *  Internal
 *      Internal View
 *      Internal Pure
 *  Private
 *      Private View
 *      Private Pure
 *
 */
pragma solidity 0.8.24;

import {IDSCEngine} from "./IDSCEngine.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts@5.1.0/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts@v1.3.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OraclesLibrary} from "./libraries/OraclesLibrary.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {CollateralManager} from "./CollateralManager.sol";
import {VaultManager} from "./VaultManager.sol";
import {Structs} from "./Structs.sol";
import {Storage} from "./Storage.sol";
import {Fees} from "./Fees.sol";
import {Liquidations} from "./Liquidation.sol";

import {console} from "forge-std/console.sol";

contract DSCEngine is Storage, Ownable, Fees, ReentrancyGuard, CollateralManager, VaultManager, Liquidations {

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    using OraclesLibrary for AggregatorV3Interface;

    /**
     * @dev Collateral data key parameters
     */

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev The address of the DSC token
     */
    DecentralizedStableCoin private immutable i_DSC;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event DscMinted(address indexed owner, uint256 amount);
    event LiquidationWithFullRewards(bytes32 indexed collId, address indexed owner, address liquidator);
    event LiquidationWithPartialRewards(bytes32 indexed collId, address indexed owner, address liquidator);
    event AbsorbedBadDebt(bytes32 indexed collId, address indexed owner);
    event LiquidationSurplusReturned(bytes32 collId, address owner, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error DSCEngine__MintingDSCFailed();
    error DSCEngine__BurningDSCFailed();
    error DSCEngine__HealthFactorBelowThreshold(uint256 healthFactor);
    error DSCEngine__VaultNotUnderwater();
    error DSCEngine__ZeroAmountNotAllowed();
    error DSCEngine__CollateralConfigurationAlreadySet(bytes32 collId);
    error DSCEngine__CollateralConfigurationCannotBeRemovedWithOutstandingDebt(uint256 debt);
    error DSCEngine__DebtSizeBelowMinimumAmountAllowed(uint256 minDebt);
    error DSCEngine__InvalidDeploymentInitializationConfigs();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier isValidDebtSize(uint256 dscAmt) {
        if (dscAmt < MIN_DEBT) {
            revert DSCEngine__DebtSizeBelowMinimumAmountAllowed(MIN_DEBT);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Initializes the DSCEngine with collateral configurations and the DSC token address.
     * Registers supported collateral types and their configuration values and establishes the contract owner.
     * @param configs Array of deployment configurations for each collateral type.
     * @param dscToken Address of the DSC token used for minting and repayment.
     */
    constructor(Structs.DeploymentConfig[] memory configs, address dscToken) Ownable(msg.sender) {
        for (uint256 k = 0; k < configs.length; k++) {
            configureCollateral(
                configs[k].collId,
                configs[k].tokenAddr,
                configs[k].liqThreshold,
                configs[k].priceFeed,
                configs[k].decimals
            );
        }

        i_DSC = DecentralizedStableCoin(dscToken);
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits ERC20 collateral and mints DSC in a single transaction.
     * @dev Requires prior token approval. Reverts if collateral amount is zero or unsupported.
     * Ensures atomicity for vault creation and DSC issuance, enhancing user experience.
     * @param collId The ID of the collateral token.
     * @param collAmt The amount of collateral to deposit.
     * @param dscAmt The amount of DSC to mint against the deposited collateral.
     */
    function depositCollateralAndMintDSC(
        bytes32 collId,
        uint256 collAmt,
        uint256 dscAmt
    )
        external
        isValidDebtSize(dscAmt)
    {
        depositCollateral(collId, collAmt);
        _mintDSC(collId, collAmt, dscAmt);
    }

    /**
     * @notice Deposits Ether collateral and mints DSC in a single transaction.
     * @dev Requires the caller to send Ether. Reverts if the amount is zero.
     * Ensures atomicity for vault creation and DSC issuance, enhancing user experience.
     * @param dscAmt The amount of DSC to mint against the deposited Ether collateral.
     */
    function depositEtherCollateralAndMintDSC(uint256 dscAmt) external payable isValidDebtSize(dscAmt) {
        addEtherCollateral();
        _mintDSC("ETH", msg.value, dscAmt);
    }

    /**
     * @notice Redeems locked collateral by burning DSC in a single transaction.
     * @dev Settles any protocol fees before redeeming. If full DSC debt is burned, the vault is considered closed,
     * and the user receives all remaining locked collateral instead of the specified amount.
     * @param collId The ID of the collateral token.
     * @param collAmt The amount of collateral to redeem.
     * @param dscAmt The amount of DSC to burn.
     */
    function redeemCollateralForDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) external {
        _burnDSC(collId, dscAmt, msg.sender, msg.sender);

        uint256 lockedBal = s_vaults[collId][msg.sender].lockedCollateral;
        uint256 actualRedeemAmt = min(lockedBal, collAmt);

        redeemCollateral(collId, actualRedeemAmt);
    }

    /**
     * @notice Expands an existing vault by adding collateral and minting additional DSC.
     * @dev Requires prior token approval and valid collateral. Reverts if inputs are invalid.
     * Ensures atomic execution of collateral deposit and DSC minting for better UX.
     * @param collId The ID of the collateral token.
     * @param collAmt The amount of collateral to deposit.
     * @param dscAmt The amount of DSC to mint.
     */
    function expandVault(bytes32 collId, uint256 collAmt, uint256 dscAmt) external isValidDebtSize(dscAmt) {
        // deposit the collateral before topping up the vault
        depositCollateral(collId, collAmt);
        addToVault(collId, collAmt, dscAmt);
    }

    /**
     * @notice Expands an existing Ether vault by adding Ether collateral and minting additional DSC.
     * @dev Requires the caller to send Ether. Reverts if the amount is zero.
     * Ensures atomic execution of Ether deposit and DSC minting for better UX.
     * @param dscAmt The amount of DSC to mint against the deposited Ether collateral.
     */
    function expandETHVault(uint256 dscAmt) external payable isValidDebtSize(dscAmt) {
        addEtherCollateral();
        addToVault("ETH", msg.value, dscAmt);
    }

    /**
     * @dev Handles internal logic for adding collateral and minting DSC after deposit.
     * Collects accrued protocol fees, updates global and vault-level accounting, and ensures vault health.
     * @param collId The ID of the collateral token.
     * @param collAmt The amount of collateral to deposit.
     * @param dscAmt The amount of DSC to mint.
     */
    function addToVault(bytes32 collId, uint256 collAmt, uint256 dscAmt) internal {
        settleProtocolFees(collId, msg.sender, s_vaults[collId][msg.sender].dscDebt);

        s_collBalances[collId][msg.sender] -= collAmt;
        s_vaults[collId][msg.sender].lockedCollateral += collAmt;
        s_vaults[collId][msg.sender].dscDebt += dscAmt;
        s_vaults[collId][msg.sender].lastUpdatedAt = block.timestamp;

        (bool healthy, uint256 hf) = isVaultHealthy(collId, msg.sender);
        if (!healthy) {
            revert DSCEngine__HealthFactorBelowThreshold(hf);
        }

        bool mintStatus = i_DSC.mint(msg.sender, dscAmt);
        if (!mintStatus) {
            revert DSCEngine__MintingDSCFailed();
        }

        emit DscMinted(msg.sender, dscAmt);
    }

    /**
     * @notice Flags a vault as underwater and optionally initiates liquidation.
     * @dev Intended for use by governance or keeper bots. Can be used to only mark or both mark and liquidate.
     * @param collId The ID of the vault collateral token.
     * @param owner The address of the vault owner.
     * @param liquidate Whether to proceed with liquidation immediately.
     * @param dsc The amount of DSC to repay if liquidating.
     * @param withdraw Whether to withdraw the proceeds of liquidation from the protocol or not. This flexibility gives
     * liquidators the option to keep the collateral within the protocol for future use such as opening new vaults
     * themselves.
     */
    function markVaultAsUnderwater(
        bytes32 collId,
        address owner,
        bool liquidate,
        uint256 dsc,
        bool withdraw
    )
        external
    {
        bool liquidatable = vaultIsUnderwater(collId, owner);
        if (liquidatable) {
            if (liquidate) {
                liquidateVault(collId, owner, dsc, withdraw);
            }
        } else {
            revert DSCEngine__VaultNotUnderwater();
        }
    }

    function liquidateVault(bytes32 collId, address owner, uint256 dscToRepay, bool withdraw) public {
        // msg.sender is the liquidator
        address liquidator = msg.sender;
        // Initiate the liquidation
        initiateLiquidation(collId, dscToRepay, owner);

        // If above call does not revert, then supplied dsc is enough, take it from liquidator
        // and burn it; but first take liquidation penalty, calculate all rewards that are dependent
        // on dsc debt since burn will remove/close the debt from vault.

        // Settle penalty first
        settleLiquidationPenalty(collId, owner, dscToRepay);

        // Calculate rewards secondly
        uint256 liquidatorRewardsUsd = calculateLiquidationRewards(collId, owner);

        // calling internal _burnDSC automatically also charges the fees and collects them
        _burnDSC(collId, dscToRepay, owner, liquidator);

        // Get the collateral tokens equivalent of the rewards
        uint256 liquidatorTokens = getTokenAmountFromUsdValue(collId, liquidatorRewardsUsd);

        // Base collateral liquidator should receive without rewards
        uint256 baseCollateral = getTokenAmountFromUsdValue(collId, dscToRepay);

        uint256 totalPayout = baseCollateral + liquidatorTokens;

        // Transfer collateral + rewards to liquidator >>>
        // The transfer involves updating the internal treasury books
        // But if the liquidator has marked withdraw as true, then the transfer will
        // further do actual sending of the tokens out of the system.
        // Otherwise the balances will reflect inside the system giving the liquidator
        // the chance of say opening vaults of their own without having to redeposit collateral.
        // If there is any excess, that will be for the vault owner

        uint256 vaultCollBal = s_vaults[collId][owner].lockedCollateral;

        // standard liquidation scenario where collateral is sufficient
        if (vaultCollBal >= totalPayout) {
            s_vaults[collId][owner].lockedCollateral -= totalPayout;
            s_collBalances[collId][liquidator] += totalPayout;
            emit LiquidationWithFullRewards(collId, owner, liquidator);
        }
        // Partial rewards but full base collateral
        // Important to note that rewards can be zero here too!
        else if (vaultCollBal >= baseCollateral) {
            s_vaults[collId][owner].lockedCollateral -= vaultCollBal; // maybe just set to zero
            s_collBalances[collId][liquidator] += vaultCollBal;
            emit LiquidationWithPartialRewards(collId, owner, liquidator);
        }
        // Protocol absorbs the vault as bad debt
        else {
            delete s_vaults[collId][owner];
            s_absorbedBadVaults[collId][address(this)] =
                Structs.Vault({lockedCollateral: vaultCollBal, dscDebt: dscToRepay, lastUpdatedAt: block.timestamp});
            emit AbsorbedBadDebt(collId, owner);

            // Then refund the liquidator their dsc that had been burnt by directly minting them new dsc
            i_DSC.mint(liquidator, dscToRepay);
        }

        // Withdraw
        if (withdraw) {
            removeCollateral(collId, s_collBalances[collId][liquidator]);
        }

        // If there is surplus, increase the balance of liquidated vault owner
        uint256 surplus = s_vaults[collId][owner].lockedCollateral;
        if (surplus > 0) {
            s_vaults[collId][owner].lockedCollateral -= surplus;
            s_collBalances[collId][owner] += surplus;
            emit LiquidationSurplusReturned(collId, owner, surplus);
        }
    }

    function depositCollateral(bytes32 collId, uint256 amount) public nonReentrant {
        addCollateral(collId, amount);
    }

    function mintDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) public isValidDebtSize(dscAmt) nonReentrant {
        _mintDSC(collId, collAmt, dscAmt);
    }

    function redeemCollateral(bytes32 collId, uint256 collAmt) public {
        _redeemVaultCollateral(collId, collAmt);
    }

    function burnDSC(bytes32 collId, uint256 dscAmt) public {
        _burnDSC(collId, dscAmt, msg.sender, msg.sender);
    }

    // morethanzero not needed here, is valid size already in mintDSC public one
    function _mintDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) internal {
        // increase their debt first
        createVault(collId, collAmt, dscAmt);

        // keep track of debt on global totals
        s_collaterals[collId].totalDebt += dscAmt;

        // Vault has to be overcollateralized as per the set configs for that collateral
        (bool healthy, uint256 healthFactor) = isVaultHealthy(collId, msg.sender);

        if (!healthy) {
            revert DSCEngine__HealthFactorBelowThreshold(healthFactor);
        }

        // Mint DSC to user address
        bool mintStatus = i_DSC.mint(msg.sender, dscAmt);

        if (!mintStatus) {
            revert DSCEngine__MintingDSCFailed();
        }
        //emit
        emit DscMinted(msg.sender, dscAmt);
    }

    function _redeemVaultCollateral(bytes32 collId, uint256 collAmt) internal {
        // shrinking shouldn't affect oc ratio
        shrinkVaultCollateral(collId, collAmt);

        (bool healthy, uint256 hf) = isVaultHealthy(collId, msg.sender);

        if (!healthy) {
            revert DSCEngine__HealthFactorBelowThreshold(hf);
        }

        // then transfer the coll to user
        removeCollateral(collId, collAmt);
    }

    function _burnDSC(bytes32 collId, uint256 dscAmt, address burnOnBehalfOf, address burnFrom) private {
        // Before burning, fees needs to be collected since the last vault update time
        // to now
        settleProtocolFees(collId, burnOnBehalfOf, dscAmt);
        // reduce their debt
        shrinkVaultDebt(collId, burnOnBehalfOf, dscAmt);

        // keep track of debt changes on global totals
        s_collaterals[collId].totalDebt -= dscAmt;

        // transfer dsc back to the engine.
        bool success = i_DSC.transferFrom(burnFrom, address(this), dscAmt);

        if (!success) {
            revert DSCEngine__BurningDSCFailed();
        }

        /// Now DSCEngine contract burns the DSC tokens.
        i_DSC.burn(dscAmt);
    }

    function settleProtocolFees(bytes32 collId, address owner, uint256 debt) internal {
        // time to charge fee for
        uint256 deltaTime = block.timestamp - s_vaults[collId][owner].lastUpdatedAt;

        uint256 accumulatedFees = calculateProtocolFee(debt, deltaTime);

        // Equivalence of these fees in collateral form
        uint256 feeTokenAmount = getTokenAmountFromUsdValue(collId, accumulatedFees);

        // collateral being charged is already in the engine. Its just a matter of
        // updating the balances treasury appropriately
        // The fee is charged from the vault's locked collateral and not the global
        // balance of the user for that collateral. This is to avoid loss because someone can
        // decide to keep their vault healthy but have zero balance on the global balances.
        // But charging the locked collateral forces the user to pay fees and not evade fees since
        // paying fees has the impact to their health factor which they will make sure to maintain
        // to avoid liquidation.
        // HF is not checked here because sometimes fee could be charged during closure which means no need
        // to enforce HF. So the calling function needs to check the HF

        // decrement locked collateral by the fee.

        s_vaults[collId][owner].lockedCollateral -= feeTokenAmount;

        // Increment the fees collected by the same amount.
        s_totalCollectedFeesPerCollateral[collId] += feeTokenAmount;

        // After paying fees, update the timestamp to now so that future payments will begin from
        // now
        // might actually not need it since shrinkVault updates too
        s_vaults[collId][owner].lastUpdatedAt = block.timestamp;
    }

    function settleLiquidationPenalty(bytes32 collId, address owner, uint256 debt) internal {
        uint256 penalty = calculateLiquidationPenalty(debt);

        uint256 penaltyTokenAmount = getTokenAmountFromUsdValue(collId, penalty);

        s_vaults[collId][owner].lockedCollateral -= penaltyTokenAmount;

        s_totalLiquidationPenaltyPerCollateral[collId] += penaltyTokenAmount;
    }

    /*//////////////////////////////////////////////////////////////
                       COLLATERAL CONFIGURATIONS
    //////////////////////////////////////////////////////////////*/
    // liquidation threshold percentage is the value from
    // Threshold = (precision * 100) / Desired Overcollateralization Ratio (%)
    // Check Deepseek chat here: https://chat.deepseek.com/a/chat/s/767f8d14-e4e1-4e89-b313-690da60cefa2

    function configureCollateral(
        bytes32 collId,
        address tokenAddr,
        uint256 liqThreshold,
        address priceFeed,
        uint8 tknDecimals
    )
        public
        onlyOwner
    {
        // Only configure supported collateral if not previously set
        if (s_collaterals[collId].tokenAddr != address(0)) {
            revert DSCEngine__CollateralConfigurationAlreadySet(collId);
        }
        s_collateralIds.push(collId);
        s_collaterals[collId].tokenAddr = tokenAddr;
        s_collaterals[collId].liqThreshold = liqThreshold;
        s_collaterals[collId].priceFeed = priceFeed;
        s_collaterals[collId].totalDebt = 0;
        s_tokenDecimals[collId] = tknDecimals; // should it be removed also at below??
    }

    function removeCollateralConfiguration(bytes32 collId) external onlyOwner {
        uint256 outstandingDebt = s_collaterals[collId].totalDebt;
        if (outstandingDebt > 0) {
            revert DSCEngine__CollateralConfigurationCannotBeRemovedWithOutstandingDebt(outstandingDebt);
        }

        delete s_collaterals[collId];

        // Gas intensive removal from array of collateral Ids
        /// this removal needs to be tested....seems incomplete the swap bit
        for (uint256 k = 0; k < s_collateralIds.length; k++) {
            if (s_collateralIds[k] == collId) {
                s_collateralIds[k] = s_collateralIds[s_collateralIds.length - 1];
                s_collateralIds.pop();
                break;
            }
        }
    }

    function getCollateralSettings(bytes32 collId) external view returns (Structs.CollateralConfig memory) {
        return s_collaterals[collId];
    }

    function getAllowedCollateralIds() external view returns (bytes32[] memory) {
        return s_collateralIds;
    }

    function getCollateralAddress(bytes32 collId) external view returns (address) {
        return s_collaterals[collId].tokenAddr;
    }

    function getVaultInformation(
        bytes32 collId,
        address owner
    )
        external
        view
        returns (uint256 collAmt, uint256 dscDebt)
    {
        collAmt = s_vaults[collId][owner].lockedCollateral;
        dscDebt = s_vaults[collId][owner].dscDebt;

        return (collAmt, dscDebt);
    }

    function getUserCollateralBalance(bytes32 collId, address user) external view returns (uint256) {
        return s_collBalances[collId][user];
    }

    function getTotalDscDebt(bytes32 collId) external view returns (uint256) {
        return s_collaterals[collId].totalDebt;
    }

    function getHealthFactor(bytes32 collId, address user) external returns (bool, uint256) {
        return isVaultHealthy(collId, user);
    }

    function calculateFees(uint256 debt, uint256 debtPeriod) external pure returns (uint256) {
        return calculateProtocolFee(debt, debtPeriod);
    }

}
