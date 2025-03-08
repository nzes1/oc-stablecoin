// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Storage} from "./Storage.sol";
import {VaultManager} from "./VaultManager.sol";

contract Liquidations is Storage, VaultManager {
    error LM__VaultNotLiquidatable();
    error LM__SuppliedDscNotEnoughToRepayBadDebt();

    function vaultIsUnderwater(
        bytes32 collId,
        address owner
    ) internal returns (bool) {
        // check if vault is undercollateralized
        (bool vaultIsHealthy, ) = isVaultHealthy(collId, owner);

        // If unhealthy, mark it as undercollateralized by storing this timestamp
        // only if not previously stored.
        if (!vaultIsHealthy) {
            // Only when zero, set it
            if (firstUnderwaterTime[collId][owner] == 0) {
                firstUnderwaterTime[collId][owner] = block.timestamp;
            }
        }

        return vaultIsHealthy;
    }

    // start auction if underwater

    // pnalty of 10%, 3% goes to protocol 7% to liquidator
    // only take debt value + penalty + any fees then return excess to owner
    // decreasing discount on collateral - this way liquidators are incentivized to act quickly.
    // To avoid liquidators not willing to liquidate small loans - perhaps due to high
    // gas costs which are justifiable by the profit they will make, then I will implement
    // minimum loan requirements so that underwater vaults are always liquidatable
    // At the minimum, pay the dsc loan. if not loan + penalty + fees; when the 3 cannot be fulfilled
    // at least do loan, or loan + fees or loan + penalty or all of them. maybe greater of
    // either loan + fees or loan + penalty -- whichever is available.
    // To avoid price impacts of large loans - supplyCap needs to be introduced.

    function initiateLiquidation(
        bytes32 collId,
        uint256 dsc,
        address owner
    ) external {
        // check underwater
        bool liquidatable = vaultIsUnderwater(collId, owner);

        if (!liquidatable) revert LM__VaultNotLiquidatable();

        // If liquidatable, cache the coll amount and debt
        uint256 dscDebt = s_vaults[collId][owner].dscDebt;

        // liquidator has to settle all debt in whole alone atm
        if (dsc != dscDebt) revert LM__SuppliedDscNotEnoughToRepayBadDebt();

        // If enough
        // Take it from liquidator and burn it
        //---this might be done on the engine
        // take protocol fees and penalty -- on engine too or vault manager
        // calculate reward
        // finally transfer collateral + reward to liquidator

        // -- might also be on the engine
    }

    function calculateLiquidationRewards(
        bytes32 collId,
        address owner
    ) public view returns (uint256 rewards) {
        uint256 totalRewards;
        // time decaying discount on collateral
        // on top add the reward per size
        (, uint256 dscDebt) = vaultDetails(collId, owner);

        // Time when the vault became undercollateralized to determine any fast paced
        // discount to liquidator
        uint256 underwaterStartTime = firstUnderwaterTime[collId][owner];

        // Discount in USD based on speed of execution.
        uint256 discount = liquidationDiscountDecay(
            underwaterStartTime,
            dscDebt
        );

        // Rewards in USD based on size of debt - more rewards for bigger vaults of debts

        uint256 rewardBasedOnDebtSize = calculateRewardBasedOnDebtSize(
            collId,
            dscDebt
        );

        // total rewards in USD/dsc amount -- needs to be converted to coll amount and transfered.
        totalRewards = discount + rewardBasedOnDebtSize;

        return totalRewards;
    }

    function liquidationDiscountDecay(
        uint256 startTime,
        uint256 dsc
    ) internal view returns (uint256 discount) {
        // get current discount %
        uint256 rate = timeDecayedLiquidationDiscountRate(startTime);

        // Since discount is applied relative to dsc amount, but charged or added to collateral
        // we can say total dsc amount = 100%
        //                         ??  = WHAT ABOUT SAY TOTAL DISCOUNT OF 3%
        // Then this applies to other rates resulting to the formula
        // discount = (rate * dsc debt amount) / 100%
        // But rate is using a precision of 18 decimals. So the 100% needs to be scaled to same precison
        /// so scale up the divisor
        // (rate * dsc debt amount) / (100 * PRECISION)

        discount = (rate * dsc) / LIQ_DISCOUNT_SCALE;
    }

    function calculateRewardBasedOnDebtSize(
        bytes32 collId,
        uint256 dscDebtSize
    ) internal view returns (uint256 reward) {
        uint256 ocr = getOCR(collId);

        // Reward for colletarals of < 150% OC = 1.5e18 or 15e17
        if (ocr < 15e17) {
            return calculateRewardForLowRiskCollateral(dscDebtSize);
        }
        // means ocr is >= to 15e17 which is high risk
        else {
            return calculateRewardForHighRiskCollateral(dscDebtSize);
        }
    }

    function timeDecayedLiquidationDiscountRate(
        uint256 startTime
    ) private view returns (uint256 discountRate) {
        // after 1 hour, return min discount %
        uint256 elapsed = block.timestamp - startTime;
        if (elapsed > LIQ_DISCOUNT_DECAY_TIME) return LIQ_DISCOUNT_END;

        // Other calculate current % in a linear interpolation formula
        // current discount = discountAtStart - ((currentTime/TotalDecayTime) * discountAtStart - discountEnd)
        // But since multiplication should be done before division: and current time is the elapsed
        // Discount start - ((elapsed * (discountStart - disocuntEnd)) / dotaldecaytime)

        uint256 discountDecayed = (elapsed *
            (LIQ_DISCOUNT_START - LIQ_DISCOUNT_END)) / LIQ_DISCOUNT_DECAY_TIME;

        // The current discount is start discount less the decayed one
        return LIQ_DISCOUNT_START - discountDecayed;
    }

    function getOCR(bytes32 collId) private view returns (uint256 ocr) {
        uint256 liqThreshold = s_collaterals[collId]
            .liquidationThresholdPercentage;

        return (PRECISION / liqThreshold);
    }

    function calculateRewardForLowRiskCollateral(
        uint256 dscDebt
    ) private pure returns (uint256 reward) {
        uint256 computedReward = (LIQ_REWARD_PER_DEBT_SIZE_LOW_RISK * dscDebt) /
            PRECISION;
        reward = min(max(computedReward, LIQ_MIN_REWARD), LIQ_MAX_REWARD);

        return reward;
    }

    function calculateRewardForHighRiskCollateral(
        uint256 dscDebt
    ) private pure returns (uint256 reward) {
        uint256 computedReward = (LIQ_REWARD_PER_DEBT_SIZE_HIGH_RISK *
            dscDebt) / PRECISION;

        reward = min(max(computedReward, LIQ_MIN_REWARD), LIQ_MAX_REWARD);

        return reward;
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a < b ? a : b);
    }

    function max(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b ? a : b);
    }
}
