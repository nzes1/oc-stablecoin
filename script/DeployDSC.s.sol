// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] private tokenAddresses;
    address[] private priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        /// prepare arguments for DSCEngine deployment.
        HelperConfig helperConfig = new HelperConfig();
        (address wETH, address wBTC, address wETHUsdPriceFeed, address wBTCUsdPriceFeed,) =
            helperConfig.activeChainNetworkConfig();
        tokenAddresses = [wETH, wBTC];
        priceFeedAddresses = [wETHUsdPriceFeed, wBTCUsdPriceFeed];

        // Deploy the DecentralizedStableCoin and DSCEngine contracts
        vm.startBroadcast();
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        /// Make DSCEngine the owner of the DecentralizedStableCoin
        dsc.transferOwnership(address(engine));

        vm.stopBroadcast();

        return (dsc, engine, helperConfig);
    }
}
