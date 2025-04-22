// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Structs} from "./Structs.sol";
/**
 * @title Protocol Storage Layout
 * @notice Contains all persistent state variables used across the DSC protocol.
 * @dev This contract defines the storage structure for vaults, collaterals, user balances,
 *      protocol-level constants, and tracking data such as collected fees or liquidation penalties.
 *      It is intended to be inherited by core logic contracts like DSCEngine and Liquidation.
 *      All variables are marked `internal` to support upgradeability or delegate-call-based architecture.
 */

contract Storage {

    // --- Protocol Constants ---

    /// @dev Number of decimals used for the DSC stablecoin.
    uint8 internal constant DSC_DECIMALS = 18;

    /// @dev Precision used for fixed-point calculations.
    uint256 internal constant PRECISION = 1e18;

    /// @dev Minimum allowable debt per vault (100 DSC).
    uint256 internal constant MIN_DEBT = 100e18;

    /// @dev Minimum required health factor to avoid liquidation (1.0).
    uint256 internal constant MIN_HEALTH_FACTOR = 1e18;

    /// @dev Initial discount applied during liquidation (3%).
    uint256 internal constant LIQ_DISCOUNT_START = 3e16;

    /// @dev Discount end value after decay (1.8%).
    uint256 internal constant LIQ_DISCOUNT_END = 18e15;

    /// @dev Time over which liquidation discount decays.
    uint256 internal constant LIQ_DISCOUNT_DECAY_TIME = 1 hours;

    /// @dev Minimum liquidation reward in DSC (10 DSC).
    uint256 internal constant LIQ_MIN_REWARD = 10e18;

    /// @dev Maximum liquidation reward in DSC (5000 DSC).
    uint256 internal constant LIQ_MAX_REWARD = 5000e18;

    /// @dev Reward rate for low-risk liquidations (0.5%).
    uint256 internal constant LIQ_REWARD_PER_DEBT_SIZE_LOW_RISK = 5e15;

    /// @dev Reward rate for high-risk liquidations (1.5%).
    uint256 internal constant LIQ_REWARD_PER_DEBT_SIZE_HIGH_RISK = 15e15;

    /// @dev Annual percentage rate (1% APR) for protocol fee.
    uint256 internal constant APR = 1e16;

    /// @dev Liquidation penalty charged to vault owner (1%).
    uint256 internal constant LIQUIDATION_PENALTY = 1e16;

    /// @dev Total number of seconds in a year.
    uint256 internal constant SECONDS_IN_YEAR = 365 days;

    // --- Vault and Collateral Data ---

    /// @dev Vaults indexed by collateral ID and owner address.
    mapping(bytes32 collId => mapping(address owner => Structs.Vault)) internal s_vaults;

    /// @dev Collateral configurations.
    mapping(bytes32 collId => Structs.CollateralConfig) internal s_collaterals;

    /// @dev User balances per collateral ID.
    mapping(bytes32 collId => mapping(address account => uint256 bal)) internal s_collBalances;

    /// @dev List of all allowed collateral IDs.
    bytes32[] internal s_collateralIds;

    /// @dev Token decimals indexed by collateral ID.
    mapping(bytes32 tkn => uint8) internal s_tokenDecimals;

    /// @dev Cached oracle decimals to reduce repeated external calls.
    mapping(bytes32 collId => Structs.OraclesDecimals) s_oracleDecimals;

    /// @dev Timestamp when vault first went underwater (used for liquidation discount decay).
    mapping(bytes32 collId => mapping(address owner => uint256 timestamp)) internal firstUnderwaterTime;

    /// @dev Fees collected per collateral type.
    mapping(bytes32 collId => uint256) internal s_totalCollectedFeesPerCollateral;

    /// @dev Total liquidation penalties collected per collateral type.
    mapping(bytes32 collId => uint256) internal s_totalLiquidationPenaltyPerCollateral;

    /// @dev Absorbed bad debt vaults that the protocol has taken over.
    mapping(bytes32 collId => mapping(address owner => Structs.Vault)) internal s_absorbedBadVaults;

}
