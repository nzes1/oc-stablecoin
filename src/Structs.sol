// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;
/**
 * @title Structs
 * @author Nzesi
 * @notice Structs used in the DSC protocol
 */

library Structs {

    struct CollateralConfig {
        address tokenAddr;
        uint256 totalDebt;
        uint256 liqThreshold; // with 18 decimals
        address priceFeed;
    }

    /**
     * @dev collateral position parameters
     */
    struct Vault {
        uint256 lockedCollateral;
        uint256 dscDebt;
        uint256 lastUpdatedAt;
    }

    struct LiquidatedVault {
        uint256 seizedCollateral;
        uint256 seizedDebt;
    }

    struct OraclesDecimals {
        bool cached;
        uint8 decimals;
    }

    struct DeploymentConfig {
        bytes32 collId;
        address tokenAddr;
        uint256 liqThreshold;
        address priceFeed;
        uint8 decimals;
    }

}
