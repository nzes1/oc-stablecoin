// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {OraclesLibrary} from "../../src/libraries/OraclesLibrary.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {AggregatorV3Interface} from "@chainlink/contracts@v1.3.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract OraclesLibraryTest is Test {

    address wethPriceFeed;
    uint256 STALENESS_THRESHOLD = 2 hours;

    using OraclesLibrary for AggregatorV3Interface;

    function setUp() public {
        // deploy a price feed for weth
        MockV3Aggregator wethFeed = new MockV3Aggregator(8, 236789e6); // $2367.89

        // save the address
        wethPriceFeed = address(wethFeed);
    }

    function test_RevertWhenPriceFeedAnswerIsOlderThanStalenessThreshold() public {
        // fast forward 12 hours
        vm.warp(block.timestamp + 12 hours);

        vm.expectRevert(OraclesLibrary.OraclesLibrary__StalePriceFeed.selector);

        AggregatorV3Interface(wethPriceFeed).latestRoundDataStalenessCheck();
    }

}
