// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts@5.1.0/mocks/token/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    DeployDSC deployer;
    Handler handler;
    address wETH;
    address wBTC;
    address wETHUsdPriceFeed;
    address wBTCUsdPriceFeed;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (wETH, wBTC, wETHUsdPriceFeed, wBTCUsdPriceFeed,) = config.activeChainNetworkConfig();

        handler = new Handler(dsc, dscEngine);

        targetContract(address(handler));

        // Fuzz variables
        bytes4[] memory fuzzSelectors = new bytes4[](2);
        fuzzSelectors[0] = Handler.depositCollateral.selector;
        fuzzSelectors[1] = Handler.redeemCollateral.selector;
        // fuzzSelectors[2] = Handler.depositAndMintDSC.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: fuzzSelectors}));
    }

    // Invariant: Total DSC token supply should always be less than the total
    // value of all the collateral locked in the system
    function invariant_TVLMustAlwaysBeGreaterThanTotalDSCSupply() public view {
        // Get total collateral
        uint256 wETHCollateral = ERC20Mock(wETH).balanceOf(address(dscEngine));
        uint256 wBTCCollateral = ERC20Mock(wBTC).balanceOf(address(dscEngine));

        // Get total value of collateral
        uint256 wETHValue = dscEngine.getValueInUSD(wETH, wETHCollateral);
        uint256 wBTCValue = dscEngine.getValueInUSD(wBTC, wBTCCollateral);
        uint256 totalCollateralValueInUSD = wETHValue + wBTCValue;

        // Get total DSC supply
        uint256 totalDSCSupply = dsc.totalSupply();

        // Assert that total value of collateral is greater than total DSC supply
        assertGe(totalCollateralValueInUSD, totalDSCSupply);
    }

    function invariant_TestRunSummary() public view {
        handler.callSummary();
    }
}
