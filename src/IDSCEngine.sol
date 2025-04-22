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
    function configureCollateral(
        bytes32 collId,
        address tokenAddr,
        uint256 liqThreshold,
        address priceFeed,
        uint8 tknDecimals
    )
        external;
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
    function getVaultInformation(
        bytes32 collId,
        address owner
    )
        external
        view
        returns (uint256 collAmt, uint256 dscDebt);
    function liquidateVault(bytes32 collId, address owner, uint256 dscToRepay, bool withdraw) external;
    function markVaultAsUnderwater(
        bytes32 collId,
        address owner,
        bool liquidate,
        uint256 dsc,
        bool withdraw
    )
        external;
    function mintDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) external;
    function owner() external view returns (address);
    function redeemCollateral(bytes32 collId, uint256 collAmt) external;
    function redeemCollateralForDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) external;
    function removeCollateral(bytes32 collId, uint256 amount) external;
    function removeCollateralConfiguration(bytes32 collId) external;
    function renounceOwnership() external;
    function transferOwnership(address newOwner) external;

}
