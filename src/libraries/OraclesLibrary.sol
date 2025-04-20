// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts@v1.3.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @dev Library for validating the freshness of Chainlink price feeds.
 * Utilizes AggregatorV3Interface to fetch the latest round data and
 * determines staleness based on the updatedAt timestamp.
 * Reverts if the price feed is older than 2 hours, indicating staleness.
 * A 2-hour threshold is chosen based on the typical 1-hour update cycle
 * of Chainlink BTC/USD and ETH/USD feeds.
 */
library OraclesLibrary {

    uint256 private constant STALE_THRESHOLD = 2 hours;

    error OraclesLibrary__StalePriceFeed();

    /**
     * @notice Verifies the freshness of the latest Chainlink price feed data.
     * @param _priceFeed The address of the Chainlink AggregatorV3Interface contract.
     * @return roundId The ID of the latest data round.
     * @return answer The reported price from the latest round.
     * @return startedAt Timestamp when the round was initiated.
     * @return updatedAt Timestamp when the round was last updated.
     * @return answeredInRound The round ID in which the answer was finalized.
     */
    function latestRoundDataStalenessCheck(AggregatorV3Interface _priceFeed)
        public
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = _priceFeed.latestRoundData();

        uint256 secondsSinceUpdate = block.timestamp - updatedAt;

        if (secondsSinceUpdate > STALE_THRESHOLD) {
            revert OraclesLibrary__StalePriceFeed();
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

}
