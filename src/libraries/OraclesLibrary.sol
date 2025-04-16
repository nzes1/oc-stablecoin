// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts@v1.3.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OraclesLibrary
 * @author @nzesi_eth
 * @notice Library to check the staleness of Chainlink price feeds. For this contract,
 * we will assume that a result that was updated 2 hours ago is stale and the system should be
 * rendered unusable. This is not recommended for production use.
 * 2 hours was selected because chainlink price feeds for BTC/USD and ETH/USD are updated every
 * 1 hour. This means that if the price feed was last updated 2 hours ago, it is stale.
 * This was part of learning the best practices for using Chainlink price feeds.
 * @dev This contract is used to check the staleness of Chainlink price feeds.
 */
library OraclesLibrary {

    uint256 private constant STALE_THRESHOLD = 2 hours;

    error OraclesLibrary__StalePriceFeed();

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
