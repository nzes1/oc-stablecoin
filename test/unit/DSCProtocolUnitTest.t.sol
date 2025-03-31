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
import {ERC20Like} from "../mocks/ERC20Like.sol";

// 0 ETH
// 1 WETH
// 2 LINK
// 3 USDT
// 4 DAI

contract DSCProtocolUnitTest is Test {
    // Core contracts
    DeployDSC deployer;
    HelperConfig helper;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    bytes32[] collIds;
    // struct Tokens{
    //     address weth;
    //     address link;
    //     address usdt;
    //     address dai;
    // }

    address TEST_USER_1 = makeAddr("Test-User-1");
    address TEST_USER_2 = makeAddr("Test-User-1");
    uint256 constant STARTING_ETH_BAL = 10_000 ether;
    uint256 constant MINT_AMOUNT = 1000_000e18; // 1M tokens
    uint256 constant DEPOSIT_AMOUNT = 1_000e18;

    event CM__CollateralDeposited(bytes32 indexed collId, address indexed depositor, uint256 amount);

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
    function test_DeploymentInitializesCollateralConfigsCorrectly() public view {
        // Arrange, act & Assert
        uint256 expectedCollCount;
        uint256 actualCollCount;

        Structs.DeploymentConfig[] memory deployedConfigs = helper.getConfigs();
        expectedCollCount = deployedConfigs.length;

        // Act

        actualCollCount = collIds.length;

        // Assertions
        // Collateral settings
        assertTrue(actualCollCount == expectedCollCount);

        for (uint256 k = 0; k < expectedCollCount; k++) {
            assertEq(collIds[k], deployedConfigs[k].collId);
            assertEq(engine.getCollateralSettings(collIds[k]).tokenAddr, deployedConfigs[k].tokenAddr);
            assertEq(engine.getCollateralSettings(collIds[k]).liqThreshold, deployedConfigs[k].liqThreshold);
            assertEq(engine.getCollateralSettings(collIds[k]).priceFeed, deployedConfigs[k].priceFeed);
        }

        // engine owned by default sender on anvil
        assertTrue(engine.owner() == address(deployer));
    }

    /*//////////////////////////////////////////////////////////////
                           PROTOCOL DEPOSITS
    //////////////////////////////////////////////////////////////*/
    function test_SuccessfulEtherDepositIncreasesUserBalance() public {
        uint256 depositAmt = 100 ether;

        vm.expectEmit(true, true, false, true);
        emit CM__CollateralDeposited(collIds[0], TEST_USER_1, depositAmt);

        vm.startPrank(TEST_USER_1);
        engine.addEtherCollateral{value: depositAmt}();
        vm.stopPrank();

        assertTrue(engine.getUserCollateralBalance(collIds[0], TEST_USER_1) == depositAmt);
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
        assertEq(emits[0].topics[0], keccak256("CM__CollateralDeposited(bytes32,address,uint256)")); // topic 0 is event signature
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

    function _mint(bytes32 collId, address user) internal {
        require(collId != "ETH", "Expected ERC20 Like token - ether supplied");
        address token = engine.getCollateralAddress(collId);
        ERC20Like(token).mint(user, MINT_AMOUNT);
    }

    function _setAllowance(bytes32 collId, address owner, uint256 amount) internal {
        require(collId != "ETH", "Expected ERC20 Like token - ether supplied");
        address recipient = address(engine);
        address token = engine.getCollateralAddress(collId);
        vm.startPrank(owner);
        ERC20Like(token).approve(recipient, amount);
        vm.stopPrank();
    }

    function _deposit(bytes32 collId, address depositor, uint256 amount) internal {
        require(collId != "ETH", "Expected ERC20 Like token - ether supplied");
        _mint(collId, depositor);
        _setAllowance(collId, depositor, amount);

        vm.startPrank(depositor);
        engine.depositCollateral(collId, amount);
        vm.stopPrank();
    }

    function test_SuccessfulErc20CollateralDepositIncreasesUserBalance() public {
        bytes32 link = collIds[2];
        _deposit(link, TEST_USER_2, DEPOSIT_AMOUNT);

        uint256 bal = engine.getUserCollateralBalance(link, TEST_USER_2);

        assertEq(bal, DEPOSIT_AMOUNT);
    }

    function test_RevertWhenDepositingZeroAmountErc20Tokens() public {
        bytes32 usdt = collIds[3];

        vm.expectRevert(CollateralManager.CM__ZeroAmountNotAllowed.selector);
        vm.startPrank(TEST_USER_2);
        engine.depositCollateral(usdt, 0);
        vm.stopPrank();
    }

    function test_RevertWhenAttemptingToDepositUninitializedErc20Token() public {
        // Create a token
        ERC20Like ARB = new ERC20Like("Arbitrum", "ARB", 18);

        vm.startPrank(TEST_USER_2);
        ARB.mint(TEST_USER_2, MINT_AMOUNT);
        ARB.approve(address(engine), DEPOSIT_AMOUNT);
        bytes32 tokenId = bytes32(bytes(ARB.symbol()));

        vm.expectRevert(CollateralManager.CM__CollateralTokenNotApproved.selector);

        engine.depositCollateral(tokenId, DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function test_SuccessfulErc20CollateralDepositEmits() public {
        bytes32 dai = collIds[3];

        vm.recordLogs();
        _deposit(dai, TEST_USER_2, DEPOSIT_AMOUNT);

        Vm.Log[] memory emits = vm.getRecordedLogs();

        // Last event is the one from the engine
        assertEq(emits[emits.length - 1].topics[0], keccak256("CM__CollateralDeposited(bytes32,address,uint256)"));

        assertEq(address(uint160(uint256(emits[emits.length - 1].topics[2]))), TEST_USER_2);
        assertEq(abi.decode(emits[emits.length - 1].data, (uint256)), DEPOSIT_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                      DEPOSITS & VAULTS ONBOARDING
    //////////////////////////////////////////////////////////////*/

    function test_MintingDscOnlySucceedsIfMinimumAmountIsMet() public {
        bytes32 link = collIds[2];
        uint256 dscAmt = 50e18; // less than Min allowed debt size
        _mint(link, TEST_USER_2);

        vm.expectPartialRevert(DSCEngine.DSCEngine__DebtSizeBelowMinimumAmountAllowed.selector);

        // Minimum mint amount is 100 dsc
        // Try to open a vault with all link deposited but mint dsc that is less than 100
        vm.startPrank(TEST_USER_2);
        engine.depositCollateralAndMintDSC(link, DEPOSIT_AMOUNT, dscAmt);
        vm.stopPrank();
    }

    function test_MintingDscCorrectlyUpdatesInternalTreasuryRecords() public {
        bytes32 weth = collIds[1];
        // OC of 170% permits up to around 1185 dsc for 1 Weth which is worth ~ $2016 (from pricefeed configs)
        uint256 dscAmt = 1185e18;
        uint256 wethAmt = 1e18; // 450 dsc needs about 765 weth
        _deposit(weth, TEST_USER_2, DEPOSIT_AMOUNT);

        vm.startPrank(TEST_USER_2);
        engine.mintDSC(weth, wethAmt, dscAmt);
        vm.stopPrank();

        uint256 collateralBal = engine.getUserCollateralBalance(weth, TEST_USER_2);

        (uint256 vaultColl, uint256 vaultDsc) = engine.getVaultInformation(weth, TEST_USER_2);

        uint256 userDscBal = dsc.balanceOf(TEST_USER_2);
        uint256 totalDscSupply = engine.getTotalDscDebt(weth);

        assertEq(collateralBal, DEPOSIT_AMOUNT - wethAmt);
        assertEq(vaultColl, wethAmt);
        assertEq(vaultDsc, dscAmt);
        assertEq(vaultDsc, userDscBal);
        assertEq(totalDscSupply, userDscBal);
        assertEq(DEPOSIT_AMOUNT, vaultColl + collateralBal);
    }

    function test_RevertWhenMintingDscBreaksHealthFactor() public {
        bytes32 usdt = collIds[3];
        // max mint out of 1000 usdt is 833.3
        // 834 breaks the OC ratio which render the HF broken
        // remember usdt has 6 decimals, so to lock 1000 usdt into a vault
        // that is 1000e6. A lot will be deposited though
        uint256 dscAmt = 834e18;
        uint256 usdtAmt = 1000e6;
        _deposit(usdt, TEST_USER_2, DEPOSIT_AMOUNT);

        vm.expectPartialRevert(DSCEngine.DSCEngine__HealthFactorBelowThreshold.selector);
        vm.startPrank(TEST_USER_2);
        engine.mintDSC(usdt, usdtAmt, dscAmt);
        vm.stopPrank();
    }

    function test_MintingDscEmits() public {
        bytes32 dai = collIds[4];
        uint256 daiAmt = 900e18;
        uint256 dscAmt = 800e18;

        _deposit(dai, TEST_USER_2, DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, true, true, address(engine));
        emit DSCEngine.DscMinted(TEST_USER_2, dscAmt);

        vm.startPrank(TEST_USER_2);
        engine.mintDSC(dai, daiAmt, dscAmt);
        vm.stopPrank();

        uint256 dscBal = dsc.balanceOf(TEST_USER_2);
        (uint256 vaultColl, uint256 vaultDsc) = engine.getVaultInformation(dai, TEST_USER_2);

        assertEq(dscBal, vaultDsc);
        assertEq(vaultColl + engine.getUserCollateralBalance(dai, TEST_USER_2), DEPOSIT_AMOUNT);
        assertEq(vaultColl, daiAmt);
    }

    function test_UserCanMintDscByDepositingEtherAsCollateral() public {
        uint256 etherAmt = 100 ether;
        uint256 dscAmt = 100_000e18; // max of ~ 118588dsc is mintable with 100 ether collateral

        vm.expectEmit(true, true, true, true, address(engine));
        emit DSCEngine.DscMinted(TEST_USER_2, dscAmt);

        vm.startPrank(TEST_USER_2);
        engine.depositEtherCollateralAndMintDSC{value: etherAmt}(dscAmt);
        vm.stopPrank();
    }

    function test_MintingDscByDepositingEtherEmits() public {
        uint256 ethAmt = 1 ether;
        uint256 dscAmt = 1185e18;

        vm.expectEmit(true, true, true, true, address(engine));
        emit CM__CollateralDeposited("ETH", TEST_USER_2, ethAmt);

        vm.startPrank(TEST_USER_2);
        engine.depositEtherCollateralAndMintDSC{value: ethAmt}(dscAmt);
    }

    /*//////////////////////////////////////////////////////////////
                       WITHDRAWALS & BURNING DSC
    //////////////////////////////////////////////////////////////*/
    function _depositCollateralAndMintDsc(
        bytes32 collId,
        address user,
        uint256 collAmt,
        uint256 lockAmt,
        uint256 dscAmt
    ) internal {
        _deposit(collId, user, collAmt);

        vm.startPrank(user);
        engine.mintDSC(collId, lockAmt, dscAmt);
        vm.stopPrank();
    }

    function test_UserCanWithdrawUnlockedErc20Collateral() public {
        bytes32 weth = collIds[1];
        uint256 wethDepositAmt = 10 ether;
        // Lock ~ 5 weth on vault
        uint256 dscAmt = 5900e18;

        // Open a vault and use only 5 weth to back dsc
        _depositCollateralAndMintDsc(weth, TEST_USER_2, wethDepositAmt, 5 ether, dscAmt);

        // Deposited 10, but opened a vault using 5.
        uint256 unlockedBal = engine.getUserCollateralBalance(weth, TEST_USER_2);

        // Unlocked should be withdrawable
        address wethAddr = engine.getCollateralAddress(weth);
        uint256 wethBalStart = ERC20Like(wethAddr).balanceOf(TEST_USER_2);

        vm.startPrank(TEST_USER_2);
        engine.removeCollateral(weth, unlockedBal);
        vm.stopPrank();

        assertEq(unlockedBal, 5 ether);
        assertEq(ERC20Like(wethAddr).balanceOf(TEST_USER_2), wethBalStart + unlockedBal);
        assertEq(engine.getUserCollateralBalance(weth, TEST_USER_2), 0);
    }

    function test_RevertWhenUserAttemptsToWithdrawZeroFromTheirUnlockedCollateralBalance() public {
        bytes32 weth = collIds[1];
        uint256 wethAmt = 20 ether;
        uint256 lockAmt = 10 ether;
        uint256 dscAmt = 11800e18;

        _depositCollateralAndMintDsc(weth, TEST_USER_2, wethAmt, lockAmt, dscAmt);

        // Attempt to withdraw 0 weth - user has 10 weth withdrawable
        vm.expectPartialRevert(CollateralManager.CM__ZeroAmountNotAllowed.selector);

        vm.startPrank(TEST_USER_2);
        engine.removeCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_RevertWhenUserAttemptsToWithdrawMoreThanTheirUnlockedCollateralBalance() public {
        bytes32 weth = collIds[1];
        uint256 wethAmt = 20 ether;
        uint256 lockAmt = 10 ether;
        uint256 dscAmt = 11800e18;

        _depositCollateralAndMintDsc(weth, TEST_USER_2, wethAmt, lockAmt, dscAmt);

        // Attempt to withdraw 11 weth - user has only 10 weth withdrawable
        vm.expectPartialRevert(CollateralManager.CM__AmountExceedsCurrentBalance.selector);

        vm.startPrank(TEST_USER_2);
        engine.removeCollateral(weth, 11 ether);
        vm.stopPrank();
    }

    function test_WithdrawalFromUnlockedErc20CollateralBalanceEmits() public {
        bytes32 usdt = collIds[3];
        uint256 usdtAmt = 140_000e6; // 140k usdt
        uint256 lockAmt = 120_000e6; // 120k usdt to mint 100k dsc
        uint256 dscAmt = 100_000e18; // 100k dsc

        _depositCollateralAndMintDsc(usdt, TEST_USER_1, usdtAmt, lockAmt, dscAmt);

        vm.recordLogs();

        vm.startPrank(TEST_USER_1);
        engine.removeCollateral(usdt, 20_000e6);
        vm.stopPrank();

        Vm.Log[] memory emits = vm.getRecordedLogs();

        // first event is the CM withdraw and the second is the transfer event from dsc
        assertEq(emits[0].topics[0], keccak256("CM__CollateralWithdrawn(bytes32,address,uint256)"));
        assertEq(emits[0].topics[1], bytes32("USDT"));
        assertEq(address(uint160(uint256(emits[0].topics[2]))), TEST_USER_1);
        assertEq(abi.decode(emits[0].data, (uint256)), 20_000e6);

        assertEq(emits[1].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(address(uint160(uint256(emits[1].topics[1]))), address(engine));
        assertEq(address(uint160(uint256(emits[1].topics[2]))), TEST_USER_1);
        assertEq(abi.decode(emits[1].data, (uint256)), 20_000e6);
    }

    function test_UserCanWithdrwaUnlockedEtherCollateralBalance() public {
        bytes32 eth = collIds[0];
        uint256 ethAmt = 150 ether;
        uint256 lockAmt = 60 ether;
        uint256 dscAmt = 71_000e18; // 60 ether can mint ~ 71,152 dsc

        uint256 ethBeforeDeposit = TEST_USER_2.balance;

        vm.startPrank(TEST_USER_2);
        engine.addEtherCollateral{value: ethAmt}();
        engine.mintDSC(eth, lockAmt, dscAmt);
        vm.stopPrank();

        uint256 ethBeforeWithdrawal = TEST_USER_2.balance;

        vm.startPrank(TEST_USER_2);
        engine.removeCollateral(eth, 90 ether);
        vm.stopPrank();

        uint256 ethAfterWithdrawal = TEST_USER_2.balance;

        assertEq(ethAfterWithdrawal, ethBeforeDeposit - lockAmt);
        assertEq(ethAfterWithdrawal, ethBeforeWithdrawal + 90 ether);
    }
}
