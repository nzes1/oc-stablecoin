// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Structs} from "../src/Structs.sol";

contract DeployDSC is Script {
    function run()
        external
        returns (DecentralizedStableCoin, DSCEngine, HelperConfig)
    {
        // /// prepare arguments for DSCEngine deployment.
        Structs.DeploymentConfig[] memory collaterals;
        HelperConfig helper = new HelperConfig();
        collaterals = helper.getDeploymentConfigs();
        // (
        //     address wETH,
        //     address wBTC,
        //     address wETHUsdPriceFeed,
        //     address wBTCUsdPriceFeed,
        // ) = helperConfig.activeChainNetworkConfig();
        // tokenAddresses = [wETH, wBTC];
        // priceFeedAddresses = [wETHUsdPriceFeed, wBTCUsdPriceFeed];
        // // Deploy the DecentralizedStableCoin and DSCEngine contracts
        // vm.startBroadcast();
        // DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        // DSCEngine engine = new DSCEngine(
        //     tokenAddresses,
        //     priceFeedAddresses,
        //     address(dsc)
        // );
        // /// Make DSCEngine the owner of the DecentralizedStableCoin
        // dsc.transferOwnership(address(engine));
        // vm.stopBroadcast();
        // return (dsc, engine, helperConfig);
    }
}
