// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Structs} from "./Structs.sol";

contract Storage {
    // DSC decimals
    uint8 internal constant DSC_DECIMALS = 18;
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
}
