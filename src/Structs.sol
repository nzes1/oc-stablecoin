// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;
/**
 * @title Structs
 * @author Nzesi
 * @notice Structs used in the DSC protocol
 */

library Structs {

    /// @dev Collateral-specific parameters
    struct CollateralConfig {
        /// @dev Address of the collateral ERC20 token.
        address tokenAddr;
        /// @dev Total DSC debt minted against this collateral type across all vaults.
        uint256 totalDebt;
        /// @dev Liquidation threshold ratio scaled to 1e18. Determines max mintable DSC relative to collateral value.
        uint256 liqThreshold;
        // @dev Address of the Chainlink price feed for this collateral.
        address priceFeed;
    }
    /// @dev Stores state of a user's vault for a specific collateral type.

    struct Vault {
        /// @dev Amount of collateral locked in the vault.
        uint256 lockedCollateral;
        /// @dev Amount of DSC debt issued against the vault.
        uint256 dscDebt;
        /// @dev Timestamp of the last update to the vault (e.g., mint, repay, adjust collateral).
        uint256 lastUpdatedAt;
    }
    /// @dev Caches the decimals returned by a collateral's price feed oracle.

    struct OraclesDecimals {
        /// @dev Indicates whether the decimals value has been cached.
        bool cached;
        /// @dev Number of decimals used by the price feed.
        uint8 decimals;
    }
    /// @dev Configuration struct used during the initial deployment of a collateral type.

    struct DeploymentConfig {
        /// @dev Unique identifier for the collateral type.
        bytes32 collId;
        /// @dev Address of the collateral token contract.
        address tokenAddr;
        /// @dev Liquidation threshold with 18 decimals precision.
        uint256 liqThreshold;
        /// @dev Address of the Chainlink price feed for the collateral.
        address priceFeed;
        /// @dev Number of decimals the collateral token uses.
        uint8 decimals;
    }

}
