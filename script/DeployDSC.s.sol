// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Structs} from "../src/Structs.sol";

contract DeployDSC is Script {
    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        /// prepare arguments for DSCEngine deployment.
        HelperConfig helper = new HelperConfig();
        Structs.DeploymentConfig[] memory deploymentConfigs = helper.getConfigs();

        // Deploy the DecentralizedStableCoin and DSCEngine contracts
        vm.startBroadcast();
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(deploymentConfigs, address(dsc));

        // change engine owner immediately to this deployer
        // Also change the owner of the dsc to the engine contract
        engine.transferOwnership(address(this));
        dsc.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (dsc, engine, helper);
    }
}
