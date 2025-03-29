// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Structs} from "../../src/Structs.sol";
import {CollateralManager} from "../../src/CollateralManager.sol";

contract DSCProtocolUnitTest is Test {
    // Core contracts
    DeployDSC deployer;
    HelperConfig helper;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    bytes32[] collIds;

    address TEST_USER_1 = makeAddr("Test-User-1");
    address TEST_USER_2 = makeAddr("Test-User-1");
    uint256 constant STARTING_ETH_BAL = 10_000 ether;

    event CM__CollateralDeposited(
        bytes32 indexed collId,
        address indexed depositor,
        uint256 amount
    );

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, helper) = deployer.run();

        collIds = engine.getAllowedCollateralIds();

        vm.deal(TEST_USER_1, STARTING_ETH_BAL);
        vm.deal(TEST_USER_2, STARTING_ETH_BAL);
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

        Structs.DeploymentConfig[] memory deployedConfigs = helper.getConfigs();
        expectedCollCount = deployedConfigs.length;

        // Act

        actualCollCount = collIds.length;

        // Asserrtions
        // Collateral settings
        assertTrue(actualCollCount == expectedCollCount);

        for (uint256 k = 0; k < expectedCollCount; k++) {
            assertEq(collIds[k], deployedConfigs[k].collId);
            assertEq(
                engine.getCollateralSettings(collIds[k]).tokenAddr,
                deployedConfigs[k].tokenAddr
            );
            assertEq(
                engine.getCollateralSettings(collIds[k]).liqThreshold,
                deployedConfigs[k].liqThreshold
            );
            assertEq(
                engine.getCollateralSettings(collIds[k]).priceFeed,
                deployedConfigs[k].priceFeed
            );
        }

        // engine owned by default sender on anvil
        assertTrue(engine.owner() == address(deployer));
    }

    /*//////////////////////////////////////////////////////////////
                   PROTOCOL ENTRY & VAULT ONBOARDING
    //////////////////////////////////////////////////////////////*/
    function test_SuccessfulEtherDepositIncreasesUserBalance() public {
        uint256 depositAmt = 100 ether;

        vm.expectEmit(true, true, false, true);
        emit CM__CollateralDeposited(collIds[0], TEST_USER_1, depositAmt);

        vm.startPrank(TEST_USER_1);
        engine.addEtherCollateral{value: depositAmt}();
        vm.stopPrank();

        assertTrue(
            engine.getUserCollateralBalance(collIds[0], TEST_USER_1) ==
                depositAmt
        );
    }

    function test_SuccessfulEtherDepositEmitsEvent() public {
        uint256 depositAmt = 100 ether;
        // collect all emitted logs
        vm.recordLogs();

        vm.startPrank(TEST_USER_1);
        engine.addEtherCollateral{value: depositAmt}();
        vm.stopPrank();

        Vm.Log[] memory emits = vm.getRecordedLogs();
        assertGt(emits.length, 0); // 1 event

        assertEq(emits[0].topics.length, 3);
        assertEq(
            emits[0].topics[0],
            keccak256("CM__CollateralDeposited(bytes32,address,uint256)")
        ); // topic 0 is event signature
        assertEq(emits[0].topics[1], collIds[0]);
        assertEq(address(uint160(uint256(emits[0].topics[2]))), TEST_USER_1);
        assertEq(abi.decode(emits[0].data, (uint256)), depositAmt);
    }

    function test_RevertWhenDepositingZeroAmountEther() public {
        vm.expectRevert(CollateralManager.CM__ZeroAmountNotAllowed.selector);

        vm.startPrank(TEST_USER_1);
        engine.addEtherCollateral();
        vm.stopPrank();
    }
}
