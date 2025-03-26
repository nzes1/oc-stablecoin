// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Structs} from "../../src/Structs.sol";

contract DSCProtocolUnitTest is Test {
    // Core contracts
    DeployDSC deployer;
    HelperConfig helper;
    DSCEngine engine;
    DecentralizedStableCoin dsc;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, helper) = deployer.run();
    }

    /*//////////////////////////////////////////////////////////////
                       ENGINE CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/
    function test_DeploymentInitializesCollateralConfigsCorrectly()
        public
        view
    {
        // Arrange, act & Assert
        uint256 expectedCollCount;
        uint256 actualCollCount;
        bytes32[] memory collIds;
        Structs.DeploymentConfig[] memory configs = helper.getConfigs();
        expectedCollCount = configs.length;

        collIds = engine.getAllowedCollateralIds();
        actualCollCount = collIds.length;

        console.log("expected", expectedCollCount);
        console.log("Actual", actualCollCount);

        assertTrue(actualCollCount == expectedCollCount);
    }
}
