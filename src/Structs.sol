// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

library Structs {
    struct CollateralConfig {
        address tokenAddr;
        uint256 totalNormalizedDebt;
        uint256 interestFee;
        uint256 liquidationThresholdPrice;
        uint256 minDebtAllowed;
        uint256 liquidationRatio;
        address priceFeedAddr;
    }

    /**
     * @dev collateral position parameters
     */
    struct Vault {
        uint256 lockedCollateral;
        uint256 dscDebt;
    }

    struct OraclesDecimals {
        bool cached;
        uint8 decimals;
    }
}
