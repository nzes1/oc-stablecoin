// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts@v1.3.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/*
 * @dev This contract is used to check the staleness of Chainlink price feeds.
 * @dev The contract uses the Chainlink AggregatorV3Interface to get the latest round data.
 * @dev The contract checks if the latest round data is stale by comparing the updatedAt timestamp
 * @dev with the current block timestamp. If the difference is greater than 2 hours, the contract
 * @dev reverts with an error.
 * @2dev 2 hours was selected because chainlink price feeds for BTC/USD and ETH/USD are
 * @dev updated every 1 hour. This means that if the price feed was last updated 2 hours ago,
 * @dev it is stale. This was part of learning the best practices for using Chainlink price feeds.
 */
library OraclesLibrary {

    uint256 private constant STALE_THRESHOLD = 2 hours;

    error OraclesLibrary__StalePriceFeed();

    /**
     * @notice Checks if the latest round data is stale.
     * @param _priceFeed The address of the Chainlink price feed.
     * @return roundId The round ID of the latest round.
     * @return answer The answer of the latest round.
     * @return startedAt The timestamp when the latest round started.
     * @return updatedAt The timestamp when the latest round was updated.
     * @return answeredInRound The round ID of the round that answered the latest round.
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
