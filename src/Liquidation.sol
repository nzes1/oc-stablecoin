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
        if (!vaultIsHealthy) {}

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
        uint256 dsc,
        address owner
    ) public {
        // time decaying discount on collateral
        // on top add the reward per size
        (uint256 collAmount, uint256 dsc) = vaultDetails(collId, owner);
    }

    function liquidationDiscountDecay() internal returns (uint256 discount) {
        // get current discount %
        uint256 rate = timeDecayedLiquidationDiscountRate();
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
}
