// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Storage} from "./Storage.sol";
import {VaultManager} from "./VaultManager.sol";

/**
 * @title Liquidations
 * @author Nzesi
 * @notice Manages the liquidation process for undercollateralized vaults and rewards calculations for liquidators.
 * @dev This contract is utilized by the DSCEngine to:
 *  - Identify undercollateralized vaults eligible for liquidation
 *  - Initiate the liquidation process
 *  - Calculate liquidation rewards in DSC (pegged 1:1 to USD),
 *    factoring in collateral type risk and time-decayed discount
 *  - Prioritize high-risk vaults for liquidation to incentivize timely actions
 *  - Ensure proper rewards calculations for liquidators while enforcing reward caps
 */
contract Liquidations is Storage, VaultManager {

    event VaultMarkedAsUnderwater(bytes32 indexed collId, address indexed owner);

    error LM__VaultNotLiquidatable();
    error LM__SuppliedDscNotEnoughToRepayBadDebt();

    /**
     * @notice Checks whether a vault is undercollateralized and flags it for liquidation.
     * @dev If the vault is undercollateralized, the function stores the current
     * timestamp as the time it was marked underwater. This timestamp is used
     * later to determine the liquidation discount for the liquidator.
     * The timestamp is only recorded once — the first time a vault is marked
     * underwater — ensuring fairness regardless of who triggers the check.
     * This mechanism allows third-party actors such as keepers or governance
     * participants to proactively mark vaults for liquidation.
     * @param collId The ID of the vault collateral type.
     * @param owner The address of the vault owner.
     * @return True if the vault is undercollateralized, false otherwise.
     */
    function vaultIsUnderwater(bytes32 collId, address owner) internal returns (bool) {
        (bool vaultIsHealthy,) = isVaultHealthy(collId, owner);
        if (!vaultIsHealthy) {
            if (firstUnderwaterTime[collId][owner] == 0) {
                firstUnderwaterTime[collId][owner] = block.timestamp;
                emit VaultMarkedAsUnderwater(collId, owner);
            }
        }

        // A vault is considered underwater if it is not healthy.
        // This can be expressed using ternary operator as:
        // return vaultIsHealthy == true ? false : true;
        // Simplified to:
        // return vaultIsHealthy ? false : true;
        // And further simplified to:
        return !vaultIsHealthy;
    }

    /**
     * @notice Performs pre-checks for liquidating an undercollateralized vault.
     * @dev Validates that the vault is underwater and that the liquidator supplies
     * sufficient DSC to cover the debt. Reverts if conditions are not met.
     * The actual liquidation execution is handled by the DSCEngine via follow-up function calls.
     * @dev Liquidators must provide the full outstanding DSC debt partial liquidations are not
     * supported in the current implementation.
     * @param collId The ID of the vault collateral type.
     * @param dsc The amount of DSC provided by the liquidator to cover the debt.
     * @param owner The address of the vault owner.
     */
    function initiateLiquidation(bytes32 collId, uint256 dsc, address owner) internal {
        bool liquidatable = vaultIsUnderwater(collId, owner);
        if (!liquidatable) revert LM__VaultNotLiquidatable();

        uint256 dscDebt = s_vaults[collId][owner].dscDebt;

        if (dsc != dscDebt) revert LM__SuppliedDscNotEnoughToRepayBadDebt();
    }

    /**
     * @notice Calculates the liquidation rewards for a liquidator based on vault details.
     * @dev Rewards are calculated in DSC and are based on the size of the debt and the speed
     * of liquidation. A time-decaying discount is applied based on how long the vault has been
     * underwater. The final rewards are returned in DSC, which is pegged to USD and will be
     * converted to collateral amount for transfer in the DSCEngine.
     * @param collId The ID of the vault collateral type.
     * @param owner The address of the vault owner.
     * @return rewards The total liquidation rewards in USD.
     */
    function calculateLiquidationRewards(bytes32 collId, address owner) public view returns (uint256 rewards) {
        uint256 totalRewards;
        (, uint256 dscDebt) = vaultDetails(collId, owner);
        uint256 underwaterStartTime = firstUnderwaterTime[collId][owner];

        uint256 discount = liquidationDiscountDecay(underwaterStartTime, dscDebt);
        uint256 rewardBasedOnDebtSize = calculateRewardBasedOnDebtSize(collId, dscDebt);

        totalRewards = discount + rewardBasedOnDebtSize;

        return totalRewards;
    }

    /**
     * @notice Calculates the liquidation discount based on the time the vault has been underwater.
     * @dev The discount is applied as a percentage of the DSC debt. The longer the vault remains
     * underwater, the lower the discount, incentivizing quicker liquidations.
     * @param startTime The timestamp when the vault was first marked as underwater.
     * @param dsc The amount of DSC debt for the vault.
     * @return discount The calculated liquidation discount in DSC or simply USD.
     */
    function liquidationDiscountDecay(uint256 startTime, uint256 dsc) internal view returns (uint256 discount) {
        uint256 rate = timeDecayedLiquidationDiscountRate(startTime);
        discount = (rate * dsc) / PRECISION;
    }

    /**
     * @notice Calculates the liquidation reward based on the size of the DSC debt.
     * @dev The reward is determined as a percentage of the debt amount, varying by collateral type risk.
     *      Collaterals with OCR < 150% are treated as low risk and earn a 0.5% reward,
     *      while those with OCR ≥ 150% are high risk and earn 1.5%. These rates are configurable per collateral
     *      and computed via helper functions. Final rewards are bounded within defined min and max limits.
     * @param collId The ID of the vault collateral type.
     * @param dscDebtSize The size of the DSC debt for the vault.
     * @return reward The calculated liquidation reward in DSC.
     */
    function calculateRewardBasedOnDebtSize(
        bytes32 collId,
        uint256 dscDebtSize
    )
        internal
        view
        returns (uint256 reward)
    {
        uint256 ocr = getOCR(collId);
        if (ocr < 15e17) {
            return calculateRewardForLowRiskCollateral(dscDebtSize);
        } else {
            return calculateRewardForHighRiskCollateral(dscDebtSize);
        }
    }

    /**
     * @notice Calculates the time-decayed liquidation discount rate.
     * @dev The discount rate starts at a maximum value of 3% and decays linearly over a 1-hour
     * period to a minimum value of 1.8%. The longer the vault remains underwater, the lower
     * the discount rate, incentivizing quicker liquidations. Past 1 hour, the discount remains at 1.8%.
     * The linear interpolation formula for calculating the decayed discount is:
     *
     * discount = discountAtStart - ((currentTime/TotalDecayTime) * (discountAtStart - discountEnd))
     * But multiplication should be done before division and `current time` is the `elapsed time`;
     * discount = discountAtStart - ((elapsed * (discountStart - discountEnd)) / totaldecaytime)
     * Where:
     *  - elapsed is the time since the vault was marked underwater.
     *  - discountAtStart is the initial maximum discount (3%).
     *  - discountEnd is the minimum discount (1.8%).
     *  - totalDecayTime is the total time for decay (1 hour).
     * @param startTime The timestamp when the vault was first marked as underwater.
     * @return discountRate The calculated liquidation discount rate in percentage.
     */
    function timeDecayedLiquidationDiscountRate(uint256 startTime) private view returns (uint256 discountRate) {
        uint256 elapsed = block.timestamp - startTime;

        if (elapsed == 0) return LIQ_DISCOUNT_START;
        if (elapsed > LIQ_DISCOUNT_DECAY_TIME) return LIQ_DISCOUNT_END;

        uint256 discountDecayed = (elapsed * (LIQ_DISCOUNT_START - LIQ_DISCOUNT_END)) / LIQ_DISCOUNT_DECAY_TIME;

        return LIQ_DISCOUNT_START - discountDecayed;
    }

    /**
     * @notice Calculates the overcollateralization ratio (OCR) for a collateral type.
     * @dev The OCR is the inverse of the liquidation threshold. It is calculated as
     * 1e18 divided by the liquidation threshold, adjusted for precision.
     * @param collId The ID of the collateral type.
     * @return ocr The calculated overcollateralization ratio.
     */
    function getOCR(bytes32 collId) private view returns (uint256 ocr) {
        uint256 liqThreshold = s_collaterals[collId].liqThreshold;

        return ((PRECISION * PRECISION) / liqThreshold);
    }

    /**
     * @notice Calculates the liquidation reward for low-risk collateral.
     * @dev The reward is calculated as 0.5% of the DSC debt size, with a minimum
     * of 10 DSC and a maximum of 5000 DSC. This ensures fair compensation for liquidators
     * while preventing excessive rewards for large debts and incentivizing action for small debts.
     * The reward is capped to prevent liquidator from receiving disproportionate rewards for large,
     * vaults and the minimum reward ensures liquidators are incentivized to act even for smaller debts.
     * @param dscDebt The amount of DSC debt for the vault.
     * @return reward The calculated liquidation reward in DSC.
     */
    function calculateRewardForLowRiskCollateral(uint256 dscDebt) private pure returns (uint256 reward) {
        uint256 computedReward = (LIQ_REWARD_PER_DEBT_SIZE_LOW_RISK * dscDebt) / PRECISION;

        reward = min(max(computedReward, LIQ_MIN_REWARD), LIQ_MAX_REWARD);

        return reward;
    }

    /**
     * @notice Calculates the liquidation reward for high-risk collateral.
     * @dev The reward is calculated as 1.5% of the DSC debt size, with a minimum
     * of 10 DSC and a maximum of 5000 DSC. This incentivizes liquidators to prioritize
     * high-risk vaults over low-risk ones. The reward is capped to prevent laiquidators
     * from receiving excessive rewards on large vaults, and the minimum reward ensures liquidators
     * are incentivized even for smaller debts.
     * @param dscDebt The amount of DSC debt for the vault.
     * @return reward The calculated liquidation reward in DSC.
     */
    function calculateRewardForHighRiskCollateral(uint256 dscDebt) private pure returns (uint256 reward) {
        uint256 computedReward = (LIQ_REWARD_PER_DEBT_SIZE_HIGH_RISK * dscDebt) / PRECISION;

        reward = min(max(computedReward, LIQ_MIN_REWARD), LIQ_MAX_REWARD);

        return reward;
    }

    /**
     * @dev Returns the minimum of two values.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a < b ? a : b);
    }

    /**
     * @dev Returns the maximum of two values.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a > b ? a : b);
    }

}
