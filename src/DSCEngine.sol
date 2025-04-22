// SPDX-License-Identifier: MIT

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
/**
 * @title DSCEngine
 * @author Nzesi
 * @notice This is the core smart contract for the protocol's stablecoin system, responsible for managing user vaults,
 * handling collateral deposits and withdrawals, minting and burning of the DSC (Decentralized Stable Coin),
 * and executing liquidations when vaults fall below their required collateral thresholds.
 *
 * @dev DSCEngine orchestrates all primary protocol interactions including:
 * - Collateral onboarding and configuration
 * - Vault lifecycle management (creation, expansion, reduction, and closure)
 * - Minting and burning of DSC in accordance with collateral ratios
 * - Fee accruals and settlement
 * - Safe and modular liquidation handling
 *
 * The contract is designed for modularity, delegating collateral configuration, health checks, fee mechanics,
 * and liquidation logic to well-scoped internal or inherited contracts.
 *
 * Access control is applied using OpenZeppelin’s Ownable. Most public-facing functions are carefully restricted,
 * and key internal state updates ensure collateral integrity and proper accounting at all times.
 *
 * @custom:styleguide This contract follows the RareSkills Solidity Style Guide:
 * https://www.rareskills.io/post/solidity-style-guide
 */

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
    /**
     * @dev Ensures that the specified DSC debt amount meets the minimum required size.
     * @param dscAmt The amount of DSC to be minted.
     */
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
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
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

    /**
     * @notice Removes a collateral configuration from the protocol.
     * @dev This function can only be called by the contract owner. It will revert if there is any outstanding debt
     * associated with the collateral type. The removal will delete the configuration for the specified collateral.
     * @param collId The unique identifier for the collateral type to be removed.
     */
    function removeCollateralConfiguration(bytes32 collId) external onlyOwner {
        uint256 outstandingDebt = s_collaterals[collId].totalDebt;
        if (outstandingDebt > 0) {
            revert DSCEngine__CollateralConfigurationCannotBeRemovedWithOutstandingDebt(outstandingDebt);
        }

        delete s_collaterals[collId];
        delete s_tokenDecimals[collId];

        for (uint256 k = 0; k < s_collateralIds.length; k++) {
            if (s_collateralIds[k] == collId) {
                s_collateralIds[k] = s_collateralIds[s_collateralIds.length - 1];
                s_collateralIds.pop();
                break;
            }
        }
    }

    /**
     * @notice Checks the health factor of a user's vault for a given collateral type.
     * @dev This function calls an internal helper function to evaluate the health factor of the user's vault.
     * It returns a boolean indicating whether the vault is healthy and the current health factor value.
     * @param collId The ID of the collateral type.
     * @param user The address of the vault owner.
     * @return A boolean indicating whether the vault is healthy and the current health factor value.
     */
    function getHealthFactor(bytes32 collId, address user) external returns (bool, uint256) {
        return isVaultHealthy(collId, user);
    }

    /**
     * @notice Retrieves the configuration settings for a specific collateral type.
     * @param collId The unique identifier for the collateral type.
     * @return The CollateralConfig struct containing the token address, total debt, liquidation threshold, and price
     * feed.
     */
    function getCollateralSettings(bytes32 collId) external view returns (Structs.CollateralConfig memory) {
        return s_collaterals[collId];
    }

    /**
     * @notice Retrieves a list of all allowed collateral IDs in the protocol.
     * @return An array of collateral IDs.
     */
    function getAllowedCollateralIds() external view returns (bytes32[] memory) {
        return s_collateralIds;
    }

    /**
     * @notice Fetches the address of the ERC20 collateral token for a given collateral ID.
     * @param collId The ID of the collateral.
     * @return The address of the collateral token.
     */
    function getCollateralAddress(bytes32 collId) external view returns (address) {
        return s_collaterals[collId].tokenAddr;
    }

    /**
     * @notice Retrieves the locked collateral amount and DSC debt for a specific vault.
     * @param collId The ID of the collateral type.
     * @param owner The address of the vault owner.
     * @return collAmt The amount of collateral locked in the vault.
     * @return dscDebt The amount of DSC debt associated with the vault.
     */
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

    /**
     * @notice Retrieves the collateral balance of a specific user for a given collateral type.
     * @dev Accesses the user's balance from the protocol's storage and is used to check how much collateral is
     * available for a user. i.e. unlocked collateral.
     * @param collId The ID of the collateral type.
     * @param user The address of the user.
     * @return The balance of the specified collateral type for the given user.
     */
    function getUserCollateralBalance(bytes32 collId, address user) external view returns (uint256) {
        return s_collBalances[collId][user];
    }

    /**
     * @notice Retrieves the total DSC debt for a specific collateral type.
     * @param collId The ID of the collateral type.
     * @return The total DSC debt associated with the specified collateral type.
     */
    function getTotalDscDebt(bytes32 collId) external view returns (uint256) {
        return s_collaterals[collId].totalDebt;
    }

    /**
     * @notice Calculates the protocol fee based on the specified debt amount and time duration.
     * @dev This function computes the fee using a fixed annual percentage rate (APR), prorated over the provided
     * debt period. The fee represents the cost of maintaining an open debt position within the protocol.
     * @param debt The outstanding DSC debt for which the fee is to be calculated.
     * @param debtPeriod The duration (in seconds) over which the debt has been active.
     * @return fee The total protocol fee owed for the specified debt and period.
     */
    function calculateFees(uint256 debt, uint256 debtPeriod) external pure returns (uint256) {
        return calculateProtocolFee(debt, debtPeriod);
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

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Deposits ERC20 collateral into the protocol.
     * @dev Updates the user's available collateral balance tracked by the protocol.
     * @param collId   //emit The ID of the collateral token.
     * @param amount The amount of collateral to deposit.
     */
    function depositCollateral(bytes32 collId, uint256 amount) public nonReentrant {
        addCollateral(collId, amount);
    }

    /**
     * @notice Redeems a specified amount of collateral from the vault.
     * @dev Allows users to withdraw collateral while maintaining their DSC debt.
     * @dev Healthy Health factor has to be maintained after redeeming.
     * @param collId The ID of the collateral token.
     * @param collAmt The amount of collateral to redeem.
     */
    function redeemCollateral(bytes32 collId, uint256 collAmt) public {
        _redeemVaultCollateral(collId, collAmt);
    }

    /**
     * @notice Mints DSC against a specified amount of collateral.
     * @dev Allows users to lock existing deposited collateral and mint DSC.
     * @param collId The ID of the collateral token.
     * @param collAmt The amount of deposited collateral to lock.
     * @param dscAmt The amount of DSC to mint against the locked collateral.
     */
    function mintDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) public isValidDebtSize(dscAmt) nonReentrant {
        _mintDSC(collId, collAmt, dscAmt);
    }

    /**
     * @notice Burns a specified amount of DSC from the user's vault.
     * @dev Decreases the DSC debt associated with the user's vault.
     *  Fees are also settled prior to reducing the debt.
     * @param collId The ID of the collateral token.
     * @param dscAmt The amount of DSC to burn.
     */
    function burnDSC(bytes32 collId, uint256 dscAmt) public {
        _burnDSC(collId, dscAmt, msg.sender, msg.sender);
    }

    /**
     * @notice Executes the liquidation of an unhealthy vault by repaying its DSC debt and seizing collateral.
     * @dev This is the core liquidation function responsible for handling the mechanics of an undercollateralized
     * vault.
     * It can be called by anyone, but the caller must supply the vault's amount of DSC to repay the debt.
     *
     * If the vault was not previously marked as underwater, the function will first flag it and apply the more generous
     * liquidation reward parameters, providing greater incentive to the liquidator. These reward mechanics are defined
     * in the Liquidation contract and ensure that early liquidators receive a premium.
     *
     * The function processes the liquidation in the following order:
     * 1. Applies a liquidation penalty, deducted from the vault owner’s locked collateral.
     * 2. Calculates liquidation rewards for the liquidator based on the DSC repaid.
     * 3. Burns the DSC supplied by the liquidator and charges protocol fees (also deducted from the owner's
     * collateral).
     *
     * Liquidation outcomes fall into one of three categories:
     *
     * 1. Sufficient Collateral for Full Liquidation:
     *    The vault has enough collateral to cover both the base repayment (i.e., collateral equivalent of DSC debt)
     *    and the calculated liquidation rewards. The liquidator receives both in full.
     *
     * 2. Partial Rewards:
     *    The vault has enough to repay the base DSC-equivalent collateral but not the full rewards.
     *    The liquidator receives the base and as much of the rewards as available. If the remaining collateral
     *    is only sufficient for base repayment, then rewards may be zero.
     *
     * 3. Insufficient Collateral (Bad Debt):
     *    The vault doesn't have enough collateral to repay even the base amount. The liquidator receives no collateral.
     *    Instead, the DSC they repaid is refunded by minting new DSC from the protocol to cover their loss.
     *    The protocol absorbs the bad debt and takes ownership of the vault. Once governance is implemented, custom
     *    rules and resolutions can be introduced to handle absorbed bad debt positions.
     *
     * If the liquidator opts to withdraw (`withdraw = true`), their rewards are sent to their address.
     * If not, the seized collateral remains in the protocol, credited to their internal balance for future use.
     *
     * Any excess collateral left after repaying DSC and rewards is returned to the vault owner.
     *
     * @param collId The ID of the collateral token.
     * @param owner The address of the vault owner.
     * @param dscToRepay The amount of DSC the liquidator is repaying to initiate liquidation.
     * @param withdraw Whether the liquidator wants to immediately withdraw the received collateral from the protocol.
     */
    function liquidateVault(bytes32 collId, address owner, uint256 dscToRepay, bool withdraw) public {
        address liquidator = msg.sender;

        initiateLiquidation(collId, dscToRepay, owner);

        settleLiquidationPenalty(collId, owner, dscToRepay);

        uint256 liquidatorRewardsUsd = calculateLiquidationRewards(collId, owner);

        _burnDSC(collId, dscToRepay, owner, liquidator);

        uint256 liquidatorTokens = getTokenAmountFromUsdValue(collId, liquidatorRewardsUsd);

        uint256 baseCollateral = getTokenAmountFromUsdValue(collId, dscToRepay);

        uint256 totalPayout = baseCollateral + liquidatorTokens;

        uint256 vaultCollBal = s_vaults[collId][owner].lockedCollateral;

        // Full rewards and full base collateral
        if (vaultCollBal >= totalPayout) {
            s_vaults[collId][owner].lockedCollateral -= totalPayout;
            s_collBalances[collId][liquidator] += totalPayout;
            emit LiquidationWithFullRewards(collId, owner, liquidator);
        }
        // Partial rewards but full base collateral
        // Important to note that rewards can be zero here too!
        else if (vaultCollBal >= baseCollateral) {
            s_vaults[collId][owner].lockedCollateral -= vaultCollBal;
            s_collBalances[collId][liquidator] += vaultCollBal;
            emit LiquidationWithPartialRewards(collId, owner, liquidator);
        }
        // Protocol absorbs the vault as bad debt
        else {
            delete s_vaults[collId][owner];
            s_absorbedBadVaults[collId][address(this)] =
                Structs.Vault({lockedCollateral: vaultCollBal, dscDebt: dscToRepay, lastUpdatedAt: block.timestamp});
            emit AbsorbedBadDebt(collId, owner);

            i_DSC.mint(liquidator, dscToRepay);
        }

        if (withdraw) {
            removeCollateral(collId, s_collBalances[collId][liquidator]);
        }

        // If there is any surplus locked collateral left in the vault after liquidation,
        // return it to the user's global balance.
        uint256 surplus = s_vaults[collId][owner].lockedCollateral;
        if (surplus > 0) {
            s_vaults[collId][owner].lockedCollateral -= surplus;
            s_collBalances[collId][owner] += surplus;
            emit LiquidationSurplusReturned(collId, owner, surplus);
        }
    }

    /**
     * @notice Configures a new collateral type with specified parameters.
     * @dev Only callable by the contract owner.
     * The function will revert if the collateral type has already been configured.
     * @param collId The unique identifier for the collateral type. e.g the token symbol.
     * @param tokenAddr The address of the ERC20 token contract representing the collateral.
     * @param liqThreshold The liquidation threshold as a percentage.
     * @param priceFeed The address of the Chainlink price feed for determining the collateral's USD value.
     * @param tknDecimals The number of decimals for the collateral token, ensuring proper scaling in calculations.
     */
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
        s_tokenDecimals[collId] = tknDecimals;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Internally handles redemption of collateral from a vault.
     * Decreases the vault's locked collateral and updates global collateral balances.
     * Ensures the vault remains healthy post-redemption by validating the health factor.
     * Reverts if the redemption would breach collateralization requirements.
     * @param collId The ID of the collateral token.
     * @param collAmt The amount of collateral to redeem.
     */
    function _redeemVaultCollateral(bytes32 collId, uint256 collAmt) internal {
        shrinkVaultCollateral(collId, collAmt);

        (bool healthy, uint256 hf) = isVaultHealthy(collId, msg.sender);
        if (!healthy) {
            revert DSCEngine__HealthFactorBelowThreshold(hf);
        }

        removeCollateral(collId, collAmt);
    }

    /**
     * @dev Mints DSC internally by locking the specified collateral amount.
     * Increases the vault's DSC debt and updates protocol-level collateral accounting.
     * Ensures the vault's health factor remains above the minimum threshold after minting.
     * Reverts if the vault would become undercollateralized.
     * @param collId The ID of the collateral token.
     * @param collAmt The amount of collateral to lock.
     * @param dscAmt The amount of DSC to mint.
     */
    function _mintDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) internal {
        createVault(collId, collAmt, dscAmt);

        s_collaterals[collId].totalDebt += dscAmt;

        (bool healthy, uint256 healthFactor) = isVaultHealthy(collId, msg.sender);
        if (!healthy) {
            revert DSCEngine__HealthFactorBelowThreshold(healthFactor);
        }

        bool mintStatus = i_DSC.mint(msg.sender, dscAmt);
        if (!mintStatus) {
            revert DSCEngine__MintingDSCFailed();
        }

        emit DscMinted(msg.sender, dscAmt);
    }

    /**
     * @dev Internally handles the burning of DSC against a vault.
     * Settles any accrued protocol fees before reducing the vault's DSC debt.
     * Supports burning on behalf of another user (e.g., during liquidation).
     * Updates accounting to reflect the new debt and ensures protocol consistency.
     * @param collId The ID of the collateral token.
     * @param dscAmt The amount of DSC to burn.
     * @param burnOnBehalfOf The vault owner whose debt is being reduced.
     * @param burnFrom The address providing the DSC to burn.
     */
    function _burnDSC(bytes32 collId, uint256 dscAmt, address burnOnBehalfOf, address burnFrom) internal {
        settleProtocolFees(collId, burnOnBehalfOf, dscAmt);

        shrinkVaultDebt(collId, burnOnBehalfOf, dscAmt);

        s_collaterals[collId].totalDebt -= dscAmt;

        bool success = i_DSC.transferFrom(burnFrom, address(this), dscAmt);
        if (!success) {
            revert DSCEngine__BurningDSCFailed();
        }

        i_DSC.burn(dscAmt);
    }

    /**
     * @dev Calculates and settles the protocol fee for a vault based on its debt and the time elapsed since
     * the last update. The fee is proportional to the amount of debt and the duration the vault has been open,
     * with an annual rate of 1%. The fee is paid in collateral, which is transferred from the vault to the protocol.
     * This function adjusts the vault’s collateral balance accordingly.
     * The calling function must ensure the vault remains healthy after the fee is settled.
     * @param collId The ID of the collateral token associated with the vault.
     * @param debt The amount of debt for which the fee is calculated.
     * @param owner The address of the vault owner.
     */
    function settleProtocolFees(bytes32 collId, address owner, uint256 debt) internal {
        uint256 deltaTime = block.timestamp - s_vaults[collId][owner].lastUpdatedAt;

        uint256 accumulatedFees = calculateProtocolFee(debt, deltaTime);
        uint256 feeTokenAmount = getTokenAmountFromUsdValue(collId, accumulatedFees);

        s_vaults[collId][owner].lockedCollateral -= feeTokenAmount;
        s_totalCollectedFeesPerCollateral[collId] += feeTokenAmount;

        s_vaults[collId][owner].lastUpdatedAt = block.timestamp;
    }

    /**
     * @dev Calculates and deducts the liquidation penalty when a vault is liquidated.
     * The penalty is 1% of the amount of DSC being repaid and is subtracted from the vault's locked collateral.
     * This fee helps incentivize liquidators and is collected in collateral tokens.
     * The function updates both the vault's collateral balance and the total liquidation penalty for the collateral
     * type.
     * @param collId The ID of the collateral token associated with the vault.
     * @param owner The address of the vault owner being liquidated.
     * @param debt The amount of DSC debt being repaid during the liquidation.
     */
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

}
