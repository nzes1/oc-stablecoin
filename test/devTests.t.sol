// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../script/DeployDSC.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";

contract DevTest is Test {
    DSCEngine dscEngine;
    DeployDSC deployer;
    HelperConfig config;
    DecentralizedStableCoin dsc;
    address wETH;
    address wBTC;
    address wETHUsdPriceFeed;
    address wBTCUsdPriceFeed;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (wETH, wBTC, wETHUsdPriceFeed, wBTCUsdPriceFeed, ) = config
            .activeChainNetworkConfig();
    }

    function test_ConfiguringNewCollateralType() public {
        bytes32 collateralId = "ETHC";
        address tokenAddr = address(22);
        uint256 interestFee = 23;
        uint256 liquidationThresholdPercentage = 500;
        uint256 minDebtAllowed = 100;
        uint256 liquidationRatio = 150;

        // owner is default sender in foundry
        vm.startPrank(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);
        dscEngine.configureCollateral(
            collateralId,
            tokenAddr,
            interestFee,
            liquidationThresholdPercentage,
            minDebtAllowed,
            liquidationRatio
        );
        vm.stopPrank();

        bytes32[] memory allowed = dscEngine.getAllowedCollateralIds();

        assertTrue(allowed[0] == bytes32("ETHC"));

        DSCEngine.CollateralConfig memory configuredColl = dscEngine
            .getCollateralSettings("ETHC");

        console.log("ETHC Addr ", configuredColl.tokenAddr);
        console.log("ETHC Fee", configuredColl.interestFee);
        console.log("ETHC total Debt", configuredColl.totalNormalizedDebt);
    }
}
