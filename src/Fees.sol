//SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Storage} from "./Storage.sol";

contract Fees is Storage {

    //Annual Percentage Rate = 1% which is 1e16

    function calculateProtocolFee(uint256 debt, uint256 deltaTime) internal pure returns (uint256) {
        //Interest = (D * r * T_in_seconds) / (SECONDS_IN_A_YEAR * 1e18)
        uint256 fee = (debt * APR * deltaTime) / (SECONDS_IN_YEAR * PRECISION);

        return fee;
    }

    function calculateLiquidationPenalty(uint256 debt) internal pure returns (uint256) {
        // liq_penalty = (debt * LIQ_PENALTY) / 1e18
        uint256 penalty = (debt * LIQUIDATION_PENALTY) / PRECISION;

        return penalty;
    }

}
