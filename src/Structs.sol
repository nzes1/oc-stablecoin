// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

library Structs {
    struct CollateralConfig {
        address tokenAddr;
        uint256 totalNormalizedDebt;
        uint256 interestFee;
        uint256 liquidationThresholdPercentage; // set it to 27 decimals
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

    struct LiquidatedVault {
        uint256 seizedCollateral;
        uint256 seizedDebt;
    }

    struct LiquidationParams {
        uint256 rewardRate;
        uint256 minReward;
        uint256 maxReward;
    }

    struct OraclesDecimals {
        bool cached;
        uint8 decimals;
    }
}
