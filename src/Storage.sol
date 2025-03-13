// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Structs} from "./Structs.sol";

contract Storage {
    // DSC decimals
    uint8 internal constant DSC_DECIMALS = 18;
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant LIQUIDATION_PRECISION = 1e27;
    uint256 internal constant MIN_HEALTH_FACTOR = 1e18;
    uint256 internal constant LIQ_DISCOUNT_START = 3e16; // 3%
    uint256 internal constant LIQ_DISCOUNT_END = 18e15; // 1.8%
    uint256 internal constant LIQ_DISCOUNT_DECAY_TIME = 1 hours;
    uint256 internal constant LIQ_DISCOUNT_SCALE = 100e18;
    uint256 internal constant LIQ_MIN_REWARD = 10e18; // 10 dsc
    uint256 internal constant LIQ_MAX_REWARD = 5000e18; // 5000 dsc
    uint256 internal constant LIQ_REWARD_PER_DEBT_SIZE_LOW_RISK = 5e15; // 0.5%
    uint256 internal constant LIQ_REWARD_PER_DEBT_SIZE_HIGH_RISK = 15e15; // 1.5%
    uint256 internal constant APR = 1e16; // 1% annual percentage rate in 18 decimals
    uint256 internal constant LIQUIDATION_PENALTY = 1e16; // 1% liquidation penalty
    uint256 internal constant SECONDS_IN_YEAR = 365 days;

    // Vaults per owner per collateral
    mapping(bytes32 collateralId => mapping(address owner => Structs.Vault))
        internal s_vaults;
    /**
     * @dev Collaterals and their configs.
     */
    mapping(bytes32 collateralId => Structs.CollateralConfig)
        internal s_collaterals;

    //User balances per collateral Id
    mapping(bytes32 collId => mapping(address account => uint256 bal))
        internal s_collBalances;

    bytes32[] internal s_collateralIds;

    // decimals of tokens
    mapping(bytes32 tkn => uint8) internal s_tokenDecimals;

    // Cache oracle decimals on first fetch to save on gas for external calls everytime
    mapping(bytes32 collId => Structs.OraclesDecimals) s_oracleDecimals;

    // Structs.LiquidationParams internal lowRiskParams; // For OC < 150%
    // Structs.LiquidationParams internal highRiskParams; // For OC >= 150%

    // underwater positions start time
    mapping(bytes32 collId => mapping(address owner => uint256 timestamp))
        internal firstUnderwaterTime;

    // Fees collected per collateral type
    mapping(bytes32 collId => uint256)
        internal s_totalCollectedFeesPerCollateral;

    mapping(bytes32 collId => uint256)
        internal s_totalLiquidationPenaltyPerCollateral;

    mapping(bytes32 collateralId => mapping(address owner => Structs.Vault))
        internal s_absorbedBadVaults;
}
