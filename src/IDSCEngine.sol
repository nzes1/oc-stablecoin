// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

library Structs {

    struct CollateralConfig {
        address tokenAddr;
        uint256 totalDebt;
        uint256 liqThreshold;
        address priceFeed;
    }

    struct DeploymentConfig {
        bytes32 collId;
        address tokenAddr;
        uint256 liqThreshold;
        address priceFeed;
        uint8 decimals;
    }

}
//// ********This is work in progress********* /////////////////
/*//////////////////////////////////////////////////////////////
                                  WIP
    //////////////////////////////////////////////////////////////*/

interface IDSCEngine {

    error CM__AmountExceedsCurrentBalance(bytes32 collId, uint256 bal);
    error CM__CollateralTokenNotApproved();
    error CM__ZeroAmountNotAllowed();
    error DSCEngine__BurningDSCFailed();
    error DSCEngine__CollateralConfigurationAlreadySet(bytes32 collId);
    error DSCEngine__CollateralConfigurationCannotBeRemovedWithOutstandingDebt(uint256 debt);
    error DSCEngine__DebtSizeBelowMinimumAmountAllowed(uint256 minDebt);
    error DSCEngine__HealthFactorBelowThreshold(uint256 healthFactor);
    error DSCEngine__InvalidDeploymentInitializationConfigs();
    error DSCEngine__MintingDSCFailed();
    error DSCEngine__VaultNotUnderwater();
    error DSCEngine__ZeroAmountNotAllowed();
    error LM__SuppliedDscNotEnoughToRepayBadDebt();
    error LM__VaultNotLiquidatable();
    error OwnableInvalidOwner(address owner);
    error OwnableUnauthorizedAccount(address account);
    error ReentrancyGuardReentrantCall();

    event AbsorbedBadDebt(bytes32 indexed collId, address indexed owner);
    event CM__CollateralDeposited(bytes32 indexed collId, address indexed depositor, uint256 amount);
    event CM__CollateralWithdrawn(bytes32 indexed collId, address indexed user, uint256 amount);
    event DscMinted(address indexed owner, uint256 amount);
    event LiquidationSurplusReturned(bytes32 collId, address owner, uint256 amount);
    event LiquidationWithFullRewards(bytes32 indexed collId, address indexed owner, address liquidator);
    event LiquidationWithPartialRewards(bytes32 indexed collId, address indexed owner, address liquidator);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event VaultMarkedAsUnderwater(bytes32 indexed collId, address indexed owner);

    function addEtherCollateral() external payable;
    function boostVault(bytes32 collId, uint256 collAmt) external;
    function burnDSC(bytes32 collId, uint256 dscAmt) external;
    function calculateFees(uint256 debt, uint256 debtPeriod) external pure returns (uint256);
    function calculateLiquidationRewards(bytes32 collId, address owner) external view returns (uint256 rewards);
    function depositCollateral(bytes32 collId, uint256 amount) external;
    function depositCollateralAndMintDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) external;
    function depositEtherCollateralAndMintDSC(uint256 dscAmt) external payable;
    function expandETHVault(uint256 dscAmt) external payable;
    function expandVault(bytes32 collId, uint256 collAmt, uint256 dscAmt) external;
    function getAllowedCollateralIds() external view returns (bytes32[] memory);
    function getCollateralAddress(bytes32 collId) external view returns (address);
    function getCollateralSettings(bytes32 collId) external view returns (Structs.CollateralConfig memory);
    function getHealthFactor(bytes32 collId, address user) external returns (bool, uint256);
    function getRawUsdValue(bytes32 collId, uint256 amount) external view returns (uint256 rawUsdValue);
    function getTokenAmountFromUsdValue(bytes32 collId, uint256 usdValue) external returns (uint256 tokenAmount);
    function getTotalDscDebt(bytes32 collId) external view returns (uint256);
    function getUserCollateralBalance(bytes32 collId, address user) external view returns (uint256);
    function getVaultCollateralUsdValue(bytes32 collId, address owner) external returns (uint256 usdValue);

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
    function liquidateVault(bytes32 collId, address owner, uint256 dscToRepay, bool withdraw) external;

    /**
     * @notice Mints DSC against a specified amount of collateral.
     * @dev Allows users to lock existing deposited collateral and mint DSC.
     * @param collId The ID of the collateral token.
     * @param collAmt The amount of deposited collateral to lock.
     * @param dscAmt The amount of DSC to mint against the locked collateral.
     */
    function mintDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) external;
    function owner() external view returns (address);
    function redeemCollateral(bytes32 collId, uint256 collAmt) external;

    /**
     * @notice Redeems locked collateral by burning DSC in a single transaction.
     * @dev Settles any protocol fees before redeeming. If full DSC debt is burned, the vault is considered closed,
     * and the user receives all remaining locked collateral instead of the specified amount.
     * @param collId The ID of the collateral token.
     * @param collAmt The amount of collateral to redeem.
     * @param dscAmt The amount of DSC to burn.
     */
    function redeemCollateralForDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) external;
    function removeCollateral(bytes32 collId, uint256 amount) external;
    function removeCollateralConfiguration(bytes32 collId) external;
    function renounceOwnership() external;
    function transferOwnership(address newOwner) external;
    function getVaultInformation(
        bytes32 collId,
        address owner
    )
        external
        view
        returns (uint256 collAmt, uint256 dscDebt);
    function configureCollateral(
        bytes32 collId,
        address tokenAddr,
        uint256 liqThreshold,
        address priceFeed,
        uint8 tknDecimals
    )
        external;

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
        external;

}
