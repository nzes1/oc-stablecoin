// SPDX-License-Identifier: MIT

// Invariant: Total DSC token supply should always be less than the total
// value of all the collateral locked in the system

pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts@5.1.0/mocks/token/ERC20Mock.sol";

/*//////////////////////////////////////////////////////////////
                    DISCLAIMER: THIS TEST IS USELESS
//////////////////////////////////////////////////////////////*/
contract OpenInvariantsTest is StdInvariant, Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    DeployDSC deployer;
    address wETH;
    address wBTC;
    address wETHUsdPriceFeed;
    address wBTCUsdPriceFeed;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (wETH, wBTC, wETHUsdPriceFeed, wBTCUsdPriceFeed,) = config.activeChainNetworkConfig();

        targetContract(address(dscEngine));
    }

    // A test invariant which is false.
    function invariant_TotalSystemCollateralValueMustAlwaysBeGreaterThanOrEqualTotalDSCSupply() public view {
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
}
