//SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Storage} from "./Storage.sol";
/**
 * @title Fees
 * @author Nzesi
 * @notice Calculates protocol fees and liquidation penalties.
 * @dev Protocol fees are collected each time vault debt changes, based on
 * accumulated fees since the last vault update. The APR is set to 1% annually.
 * Liquidation penalty is a one-time fee of 1% on the DSC debt at the time of
 * liquidation, regardless of time.
 *
 * @dev All fee values returned by this contract are denominated in DSC,
 * which maintains a 1:1 peg with USD.
 */

contract Fees is Storage {

    /**
     * @dev Calculates the protocol fee based on vault debt and time since last update.
     * Fees are collected whenever the vault debt changes, with the time elapsed
     * determining the fee accumulation.
     * Formula: protocolFee = (D * r * T_in_seconds) / (SECONDS_IN_A_YEAR * 1e18)
     * Where:
     *  - D is the debt of the vault
     *  - r is the annual interest rate (APR) which is 1%, 1e16 in 18 decimals.
     *  - T_in_seconds is the time elapsed since the last update
     *  - SECONDS_IN_A_YEAR is the number of seconds in a year (typically 365 days)
     *  - 1e18 maintains precision for fixed-point math
     * @param debt The current debt of the vault.
     * @param deltaTime The time elapsed since the last fee collection, in seconds.
     * @return fee The calculated protocol fee.
     */
    function calculateProtocolFee(uint256 debt, uint256 deltaTime) internal pure returns (uint256) {
        uint256 fee = (debt * APR * deltaTime) / (SECONDS_IN_YEAR * PRECISION);
        return fee;
    }

    /**
     * @dev Calculates the liquidation penalty based on the vault's debt.
     * This is a one-time fee equal to 1% of the DSC debt at the moment of liquidation.
     * Formula: penalty = (debt * LIQUIDATION_PENALTY_RATE) / 1e18
     * Where:
     *  - debt is the outstanding DSC debt of the vault
     *  - LIQUIDATION_PENALTY_RATE is the penalty rate (1%)
     *  - 1e18 maintains precision for fixed-point math
     * @param debt The current debt of the vault.
     * @return penalty The calculated liquidation penalty.
     */
    function calculateLiquidationPenalty(uint256 debt) internal pure returns (uint256) {
        uint256 penalty = (debt * LIQUIDATION_PENALTY) / PRECISION;
        return penalty;
    }

}
