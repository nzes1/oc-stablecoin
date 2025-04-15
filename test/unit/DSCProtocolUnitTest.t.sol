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
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

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
    uint256 constant MINT_AMOUNT = 100_000_000e18; // 100M tokens
    uint256 constant DEPOSIT_AMOUNT = 1_000e18;

    event CM__CollateralDeposited(bytes32 indexed collId, address indexed depositor, uint256 amount);
    event VaultMarkedAsUnderwater(bytes32 indexed collId, address indexed owner);
    event LiquidationWithFullRewards(bytes32 indexed collId, address indexed owner, address liquidator);
    event LiquidationWithPartialRewards(bytes32 indexed collId, address indexed owner, address liquidator);
    event AbsorbedBadDebt(bytes32 indexed collId, address indexed owner);

    error LM__SuppliedDscNotEnoughToRepayBadDebt();
    error LM__VaultNotLiquidatable();
    error OwnableUnauthorizedAccount(address account);

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

    function test_RevertWhenConfiguringAnAlreadyConfiguredCollateralType() public {
        // Attempt to reconfigure LINK which is already set during deployment.
        bytes32 collId = "LINK";
        address tokenAddr = makeAddr("Fake Link Address");
        uint256 liqThreshold = 625000000000000000;
        address priceFeed = makeAddr("LINK token price feed address");
        uint8 linkDecimals = 18;

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__CollateralConfigurationAlreadySet.selector, collId));

        vm.startPrank(address(deployer));
        engine.configureCollateral(collId, tokenAddr, liqThreshold, priceFeed, linkDecimals);
        vm.stopPrank();
    }

    function test_RevertWhenNonAdminAttemptsToAddNewCollateralSupportToTheProtocol() public {
        bytes32 collId = "DOGE";
        address tokenAddr = makeAddr("Fake DOGE Address");
        uint256 liqThreshold = 625000000000000000;
        address priceFeed = makeAddr("DOGE token price feed address");
        uint8 dogeDecimals = 8;

        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, TEST_USER_1));

        vm.startPrank(TEST_USER_1);
        engine.configureCollateral(collId, tokenAddr, liqThreshold, priceFeed, dogeDecimals);
        vm.stopPrank();
    }

    function test_AdminCanConfigureAdditionalCollateralPostDeployment() public {
        // USDC on sepolia
        bytes32 collId = "USDC";
        address tokenAddr = 0xf08A50178dfcDe18524640EA6618a1f965821715;
        uint256 liqThreshold = 833333333333333333; // 120% OC
        address priceFeed = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
        uint8 usdcDecimals = 6;

        vm.startPrank(address(deployer));
        engine.configureCollateral(collId, tokenAddr, liqThreshold, priceFeed, usdcDecimals);
        vm.stopPrank();

        bytes32[] memory allowedCollaterals = engine.getAllowedCollateralIds();

        assertEq(allowedCollaterals.length, 6); // 5 were added during deployment
        assertEq(allowedCollaterals[allowedCollaterals.length - 1], collId);
    }

    function test_RevertWhenAdminAttemptsRemovalOfCollateralConfigurationThatHasOpenVaults() public {
        // Open a LINK vault
        bytes32 link = collIds[2];
        uint256 linkAmt = 110e18; // mints ~ 1000 dsc
        uint256 dscAmt = 1000e18;

        _depositCollateralAndMintDsc(link, TEST_USER_2, linkAmt, linkAmt, dscAmt);

        // Admin attempts to remove LINK configurations
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__CollateralConfigurationCannotBeRemovedWithOutstandingDebt.selector, dscAmt
            )
        );

        vm.startPrank(address(deployer));
        engine.removeCollateralConfiguration(link);
        vm.stopPrank();
    }

    function test_AdminCanRemoveCollateralConfiguration() public {
        // Collaterals are indexed as follows;
        // ETH, WETH, LINK, USDT, DAI
        // Removing LINK position DAI at position 2 and USDT becomes the last ID on the array
        bytes32[] memory allowedCollateralsStart = engine.getAllowedCollateralIds();

        vm.startPrank(address(deployer));
        engine.removeCollateralConfiguration(collIds[2]);
        vm.stopPrank();

        bytes32[] memory allowedCollateralsEnd = engine.getAllowedCollateralIds();

        assertEq(engine.getCollateralAddress(collIds[2]), address(0));
        assertLt(allowedCollateralsEnd.length, allowedCollateralsStart.length);
        assertEq(allowedCollateralsEnd[2], "DAI");
        assertEq(allowedCollateralsEnd[allowedCollateralsEnd.length - 1], "USDT");
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
        assertEq(emits[0].topics[0], keccak256("CM__CollateralDeposited(bytes32,address,uint256)")); // topic 0 is event
            // signature
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

    function test_UsersCanOnlyIncreaseVaultDebtWithDscAmountMoreThanOrEqualToMinimumSet() public {
        bytes32 usdt = collIds[3];
        uint256 dscAmt = 50e18; // less than Min allowed debt size
        _mint(usdt, TEST_USER_2);

        vm.expectPartialRevert(DSCEngine.DSCEngine__DebtSizeBelowMinimumAmountAllowed.selector);

        // Minimum mint amount is 100 dsc
        // Try to open a vault with all usdt deposited but mint dsc that is less than 100
        vm.startPrank(TEST_USER_2);
        engine.expandVault(usdt, DEPOSIT_AMOUNT, dscAmt);
        vm.stopPrank();
    }

    function test_UsersCanExpandVaultsByAddingMoreCollateralAndRequestingMoreDsc() public {
        bytes32 weth = collIds[1];
        uint256 wethFirstDeposit = 60 ether;
        // 60 ether allows ~ 71152 dsc. Leaving a 52 dsc buffer for fees
        uint256 dscFirstMint = 71_100e18;
        uint256 wethSecondDeposit = 30 ether;
        // 30 ether allows ~ 35576 dsc
        uint256 dscSecondMint = 35_000e18;
        uint256 nineMonths = 272 days;

        _depositCollateralAndMintDsc(weth, TEST_USER_1, wethFirstDeposit, wethFirstDeposit, dscFirstMint);

        // Fast forward, 9 months later
        vm.warp(block.timestamp + nineMonths);
        // Update priceFeed with same price so as not to be stale
        MockV3Aggregator(engine.getCollateralSettings(weth).priceFeed).updateAnswer(201635e6);

        uint256 nineMonthsFeesInWeth =
            engine.getTokenAmountFromUsdValue2(weth, engine.calculateFees(dscFirstMint, nineMonths));

        vm.startPrank(TEST_USER_1);
        // First pre-approve engine before expanding the vault
        ERC20Like(engine.getCollateralSettings(weth).tokenAddr).approve(address(engine), wethSecondDeposit);
        // Then do the expansion
        engine.expandVault(weth, wethSecondDeposit, dscSecondMint);
        vm.stopPrank();

        (uint256 totalLocked, uint256 currentDebt) = engine.getVaultInformation(weth, TEST_USER_1);

        assertEq(totalLocked, wethFirstDeposit + wethSecondDeposit - nineMonthsFeesInWeth);
        assertEq(currentDebt, dscFirstMint + dscSecondMint);
    }

    function test_UsersCanExpandVaultsBackedByETH() public {
        bytes32 eth = collIds[0];
        uint256 ethFirstDeposit = 12 ether;
        // 12 ether allows ~ 14230 dsc with OC of 170%
        uint256 dscFirstMint = 14_000e18;
        uint256 ethSecondDeposit = 11 ether;
        // 11 ether allows ~ 13044 dsc
        uint256 dscSecondMint = 12_500e18;
        uint256 sixMonths = 182 days;

        vm.startPrank(TEST_USER_1);
        engine.depositEtherCollateralAndMintDSC{value: ethFirstDeposit}(dscFirstMint);
        vm.stopPrank();

        (uint256 initialColl, uint256 initialDebt) = engine.getVaultInformation(eth, TEST_USER_1);

        assertEq(initialColl, ethFirstDeposit);
        assertEq(initialDebt, dscFirstMint);

        // Fast forward and update price to avoid staleness
        vm.warp(block.timestamp + sixMonths);

        // ETH relies on WETH price, so we can update weth price feed
        MockV3Aggregator(engine.getCollateralSettings(collIds[1]).priceFeed).updateAnswer(201635e6);

        vm.expectEmit(true, true, true, false, address(engine));
        emit DSCEngine.DscMinted(TEST_USER_1, dscSecondMint);
        // Expand vault
        vm.startPrank(TEST_USER_1);
        engine.expandETHVault{value: ethSecondDeposit}(dscSecondMint);
        vm.stopPrank();

        uint256 sixMonthsFeesInEth =
            engine.getTokenAmountFromUsdValue2(eth, engine.calculateFees(dscFirstMint, sixMonths));

        (uint256 finalColl, uint256 finalDebt) = engine.getVaultInformation(eth, TEST_USER_1);

        assertEq(finalColl, initialColl + ethSecondDeposit - sixMonthsFeesInEth);
        assertEq(finalDebt, dscFirstMint + dscSecondMint);
    }

    function test_ExpandingVaultRevertsIfHFFallBelowThreshold() public {
        bytes32 weth = collIds[1];
        uint256 wethFirstDeposit = 12 ether;
        // 12 ether allows ~ 14230 dsc with OC of 170%
        uint256 dscFirstMint = 14_000e18;
        uint256 wethSecondDeposit = 11 ether;
        // 11 ether allows ~ 13044 dsc
        uint256 dscSecondMint = 13_300e18;
        uint256 sixMonths = 182 days;

        _depositCollateralAndMintDsc(weth, TEST_USER_2, wethFirstDeposit, wethFirstDeposit, dscFirstMint);

        (uint256 initialColl, uint256 initialDebt) = engine.getVaultInformation(weth, TEST_USER_2);

        assertEq(initialColl, wethFirstDeposit);
        assertEq(initialDebt, dscFirstMint);

        // Fast forward and update price to avoid staleness
        vm.warp(block.timestamp + sixMonths);

        // ETH relies on WETH price, so we can update weth price feed
        MockV3Aggregator(engine.getCollateralSettings(collIds[1]).priceFeed).updateAnswer(201635e6);

        // Expanding vault reverts because the health factor is broken since dsc being added is more
        // than the supplied collateral
        vm.startPrank(TEST_USER_1);
        ERC20Like(engine.getCollateralAddress(weth)).approve(address(engine), dscSecondMint);
        vm.expectPartialRevert(DSCEngine.DSCEngine__HealthFactorBelowThreshold.selector);
        engine.expandVault(weth, wethSecondDeposit, dscSecondMint);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              WITHDRAWALS
    //////////////////////////////////////////////////////////////*/
    function _depositCollateralAndMintDsc(
        bytes32 collId,
        address user,
        uint256 collAmt,
        uint256 lockAmt,
        uint256 dscAmt
    )
        internal
    {
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

    function test_UserCanWithdrawUnlockedEtherCollateralBalance() public {
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

    function test_RevertWhenWithdrawalOfUnlockedEtherCollateralFails() public {
        bytes32 eth = collIds[0];
        uint256 ethAmt = 2 ether;
        uint256 dscAmt = 1100e18;
        uint256 lockAmt = 1 ether;

        // Simulate withdrawal to a dummy contract address
        address dummyContract = makeAddr("dummyContract");
        Dummy dummy = new Dummy();
        bytes memory dummyCode = address(dummy).code;
        vm.etch(dummyContract, dummyCode); // Setting the code to that of dummy contract

        vm.deal(dummyContract, 5 ether); // setting contract balance to 5 ether

        vm.startPrank(dummyContract);
        engine.addEtherCollateral{value: ethAmt}();
        engine.mintDSC(eth, lockAmt, dscAmt); // user still has 1 ether that is unlocked
        vm.stopPrank();

        uint256 ethBeforeWithdrawal = address(dummyContract).balance;

        vm.expectRevert(bytes("Ether Transfer Failed"));
        vm.startPrank(dummyContract);
        engine.removeCollateral(eth, 1 ether);
        vm.stopPrank();

        uint256 ethAfterWithdrawal = address(dummyContract).balance;

        assertEq(ethBeforeWithdrawal, ethAfterWithdrawal);
        assertEq(engine.getUserCollateralBalance(eth, address(dummyContract)), 1 ether);
    }

    function test_UserCanRedeemExcessCollateralFromVault() public {
        // Arrange act assertions
        bytes32 dai = collIds[4];
        uint256 daiAmt = 30_000e18;
        uint256 lockAmt = 25_000e18;
        uint256 dscAmt = 20_000e18;
        uint256 excessLocked = 2_000e18;

        // Open vault with excess of ~2.3k dai
        // OC is 110% and with 25k dai, can mint ~ 22727 dsc
        _depositCollateralAndMintDsc(dai, TEST_USER_2, daiAmt, lockAmt, dscAmt);

        address daiAddr = engine.getCollateralAddress(dai);
        uint256 daiBefore = ERC20Like(daiAddr).balanceOf(TEST_USER_2);

        // Redeem sends the excess back to user's wallet and not internal treasury records
        vm.startPrank(TEST_USER_2);
        engine.redeemCollateral(dai, excessLocked);
        vm.stopPrank();

        uint256 daiAfter = ERC20Like(daiAddr).balanceOf(TEST_USER_2);

        // Redeemed collateral hits their wallet
        assertEq(daiAfter, daiBefore + excessLocked);
    }

    function test_RevertWhenUserAttemptsToRemoveExcessVaultCollateralThatBreaksHealthFactor() public {
        // Arrange act assertions
        bytes32 dai = collIds[4];
        uint256 daiAmt = 30_000e18;
        uint256 lockAmt = 25_000e18; // worth $25002 because dai was valued at $1.0001
        uint256 dscAmt = 20_000e18; // needs around 22k dai

        // Open vault with excess of ~2.3k dai
        // OC is 110% and with 25k dai, can mint ~ 22727 dsc
        _depositCollateralAndMintDsc(dai, TEST_USER_2, daiAmt, lockAmt, dscAmt);

        vm.expectPartialRevert(DSCEngine.DSCEngine__HealthFactorBelowThreshold.selector);

        // Excess is ~ $3002 worth of dai which is around 3000 dai
        // Attempting to redeem 3010 dai will revert as that breaks HF.
        vm.startPrank(TEST_USER_2);
        engine.redeemCollateral(dai, 3010e18);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                     BURNING TOKENS & VAULT CLOSURE
    //////////////////////////////////////////////////////////////*/

    function test_UsersCanSuccessfullyBurnTheirTokensProvidedHFDoesNotBreakAfterFeesAreCollected() public {
        bytes32 link = collIds[2];
        uint256 linkAmt = 1000e18;
        uint256 lockAmt = 900e18;
        uint256 dscAmt = 500e18; // Requires ~ 800 link
        uint256 oneYear = 365 days;

        _depositCollateralAndMintDsc(link, TEST_USER_1, linkAmt, lockAmt, dscAmt);

        // A buffer of 100 link already exists: 500 dsc => 800 link
        // for an OC of 160%.
        // This buffer will be used for fees. Assuming a debt period of 1 year = 365 days
        // Max fee of 1% = 1% * 500 dsc = 5 dsc =~ $5 worth of link =~ 0.38875 link
        // Fees = (APR  * debt * time) / (1 Yr * Precision )
        // Precision used to scale down the 36 decimals resulting from * APR and ebt
        uint256 expectedFees = (1e16 * dscAmt * oneYear) / (oneYear * 1e18);
        uint256 calculatedFees = engine.calculateFees(dscAmt, oneYear);
        address linkFeed = engine.getCollateralSettings(link).priceFeed;
        uint256 linkBefore = dsc.balanceOf(TEST_USER_1);

        vm.startPrank(TEST_USER_1);
        // Approve engine to use dsc
        dsc.approve(address(engine), dscAmt);
        // Simulate 1 year passing
        vm.warp(block.timestamp + oneYear);
        // Update/refresh price feed to end of year but maintain prices
        MockV3Aggregator(linkFeed).updateAnswer(1474e6);
        // Burn dsc
        engine.burnDSC(link, dscAmt); // Burn all dsc
        vm.stopPrank();

        // Burn should succeed
        (uint256 linkAfter, uint256 debtAfter) = engine.getVaultInformation(link, TEST_USER_1);
        uint256 feesInLink = engine.getTokenAmountFromUsdValue2(link, calculatedFees);
        uint256 linkEnd = dsc.balanceOf(TEST_USER_1);

        assertEq(expectedFees, calculatedFees);
        assertEq(debtAfter, 0);
        assertEq(linkAfter, lockAmt - feesInLink);
        assertEq(linkEnd, linkBefore - dscAmt);
    }

    function test_UsersCanCloseVaultsByPayingDebtBackToTheProtocolAndRedeemingTheirCollateral() public {
        bytes32 link = collIds[2];
        uint256 linkAmt = 1000e18;
        uint256 lockAmt = 900e18;
        uint256 dscAmt = 500e18; // Requires ~ 800 link
        uint256 nineMonths = 272 days; // ~273.75 days
        address linkFeed = engine.getCollateralSettings(link).priceFeed;
        address linkToken = engine.getCollateralAddress(link);

        _depositCollateralAndMintDsc(link, TEST_USER_1, linkAmt, lockAmt, dscAmt);

        // Balance of user's link before vault closure
        uint256 startLinkBal = ERC20Like(linkToken).balanceOf(TEST_USER_1);
        uint256 startTotalLinkDsc = engine.getTotalDscDebt(link);

        vm.startPrank(TEST_USER_1);
        // Approve engine to use dsc
        dsc.approve(address(engine), dscAmt);
        // Simulate nine months passing
        vm.warp(block.timestamp + nineMonths);
        // Update/refresh price feed to end of year but maintain prices
        MockV3Aggregator(linkFeed).updateAnswer(1474e6);
        // Burn all dsc and withdrawal all locked collateral
        engine.redeemCollateralForDSC(link, lockAmt, dscAmt);
        vm.stopPrank();

        // Combined the raw fees in USD and the actual tokens into one call as two
        // local variables were causing the infamous `stack too deep error`
        // uint256 feesUsd = engine.calculateFees(dscAmt, nineMonths);
        uint256 feesInLinkTokens = engine.getTokenAmountFromUsdValue2(link, (engine.calculateFees(dscAmt, nineMonths)));

        (uint256 lockedBal, uint256 debt) = engine.getVaultInformation(link, TEST_USER_1);
        uint256 endLinkBal = ERC20Like(linkToken).balanceOf(TEST_USER_1);
        uint256 endTotalLinkDsc = engine.getTotalDscDebt(link);

        assertEq(lockedBal, 0);
        assertEq(debt, 0);
        assertEq(endLinkBal, startLinkBal + lockAmt - feesInLinkTokens);
        assertEq(endTotalLinkDsc, startTotalLinkDsc - dscAmt);
    }

    function test_UsersCanPartiallyShrinkVaultsAndWithdrawLockedCollateralIfHFRemainsSafe() public {
        bytes32 link = collIds[2];
        uint256 linkAmt = 1000e18;
        uint256 lockAmt = 900e18;
        uint256 dscAmt = 500e18; // Requires ~ 800 link

        // Burning 200 DSC leaves 300 DSC in the vault, requiring a 160% OC.
        // This means 480 LINK must remain locked.
        //
        // Fees are deducted when burning 200 DSC.
        // A redeem request of 400 LINK succeeds, leaving 20 LINK to cover:
        //  - Fees for this redemption.
        //  - Future fees on the remaining 300 DSC.
        //
        // This test can be duplicated and extended to test future burns.
        // A separate test should handle burning the remaining DSC.
        // That test may require the `via-ir` flag due to `stack too deep` issues
        // with the default compiler.
        uint256 burnDsc = 200e18;
        uint256 collToRedeem = 400e18;
        uint256 nineMonths = 272 days; // ~273.75 days
        address linkFeed = engine.getCollateralSettings(link).priceFeed;
        address linkToken = engine.getCollateralAddress(link);

        _depositCollateralAndMintDsc(link, TEST_USER_1, linkAmt, lockAmt, dscAmt);

        uint256 startLinkBal = ERC20Like(linkToken).balanceOf(TEST_USER_1);

        vm.startPrank(TEST_USER_1);
        // Approve engine to use dsc
        dsc.approve(address(engine), dscAmt);
        // Simulate nine months passing
        vm.warp(block.timestamp + nineMonths);
        // Update/refresh price feed to end of year but maintain prices
        MockV3Aggregator(linkFeed).updateAnswer(1474e6);
        // Burn all dsc and withdrawal all locked collateral
        engine.redeemCollateralForDSC(link, collToRedeem, burnDsc);
        vm.stopPrank();

        (uint256 lockedBal, uint256 debt) = engine.getVaultInformation(link, TEST_USER_1);
        uint256 feesInLinkTokens = engine.getTokenAmountFromUsdValue2(link, (engine.calculateFees(burnDsc, nineMonths)));
        uint256 endLinkBal = ERC20Like(linkToken).balanceOf(TEST_USER_1);

        assertEq(endLinkBal, startLinkBal + collToRedeem);
        assertEq(lockedBal, lockAmt - collToRedeem - feesInLinkTokens);
        assertEq(debt, dscAmt - burnDsc);
    }

    /*//////////////////////////////////////////////////////////////
                        PRICE FEED CALCULATIONS
    //////////////////////////////////////////////////////////////*/
    function test_VaultHealthFactorFIsCalculatedCorrectly() public {
        // HF (Health Factor) = Ratio of trusted collateral to minted DSC.
        //
        // Trusted collateral is the portion of collateral (in USD value)
        // that is considered safe based on the liquidation threshold (LT).
        //
        // Example (for an Overcollateralization (OC) of 150%):
        // - Liquidation Threshold (LT) = (100 * 100) / 150 = 66.67%
        // - Trusted Collateral = (66.67 / 100) * Total Collateral USD Value
        //
        // The first 100 is for precision, meaning real calculations use **1e18**.
        // Since LT is stored with 18 decimals, **66.67% = 666666666666666666 (1e18 format)**.
        bytes32 link = collIds[2];
        uint256 linkAmt = 60_000e18;
        uint256 lockAmt = 57_750e18;
        // 57750 link can mint ~ 532,021.875 dsc
        uint256 dscAmt = 520_000e18;
        uint256 calculatedHF;
        uint256 actualHF;

        _depositCollateralAndMintDsc(link, TEST_USER_2, linkAmt, lockAmt, dscAmt);

        // LINK has an OC of 160%
        uint256 LT = (1e18 * 100) / 160;
        // Since LT is a % of 18 decimals, we divide by 1e18. Its like saying 10%
        // and in a calculation you write it as 10/100 where 100 is the decimals
        uint256 trustedCollateral = (LT * lockAmt) / 1e18;

        // The usd value here has decimals equal to those of price feed
        // link feed has 8 decimals and thus the result loses some value in this case
        // We scale it to 18 decimals since dsc has 18 decimals
        uint256 trustedCollUsd = (engine.getRawUsdValue(link, trustedCollateral)) * 10 ** 10;

        // Both trustedColl and dscAmt now have 18 decimals. Dividing them removes the 18 decimals
        // so maintain the 18 decimals, we multiply by 18decimals
        calculatedHF = (trustedCollUsd * 1e18) / dscAmt;
        (, actualHF) = engine.getHealthFactor(link, TEST_USER_2);

        assertEq(calculatedHF, actualHF);
    }

    function test_VaultUSDValueIsCalculatedCorrectly() public {
        bytes32 weth = collIds[1];
        uint256 wethAmt = 1270 ether;
        uint256 lockAmt = 1255 ether;
        uint256 dscAmt = 1_000_000e18;
        uint256 calculatedUsdValue;
        uint256 actualUsdValue;
        uint256 wethUsdPrice = 201635e6; // 8 decimals => $2016.35

        _depositCollateralAndMintDsc(weth, TEST_USER_2, wethAmt, lockAmt, dscAmt);

        // 1 weth = wethUsdPrice
        // some weth = ?
        // (some weth * wethUsdPrice)/ 1 weth
        // And 1 weth = 1e18

        uint256 usdValue = (lockAmt * wethUsdPrice) / 1e18; // Results to a value with 8 decimals.
        calculatedUsdValue = usdValue * 10 ** 10;

        actualUsdValue = engine.getVaultCollateralUsdValue(weth, TEST_USER_2);

        assertEq(calculatedUsdValue, actualUsdValue);
    }

    /*//////////////////////////////////////////////////////////////
                              LIQUIDATIONS
    //////////////////////////////////////////////////////////////*/
    function _mockPriceChange(bytes32 collId, int256 newPrice) internal {
        address priceFeed = engine.getCollateralSettings(collId).priceFeed;
        MockV3Aggregator(priceFeed).updateAnswer(newPrice);
    }

    function test_RevertWhenMarkingHealthyVaultAsUnderwater() public {
        bytes32 link = collIds[2];
        uint256 linkAmt = 1000e18;
        // 1000 link allows minting ~ 9212 dsc
        uint256 dscAmt = 8000e18;
        // liquidator
        uint256 liquidatorDsc = 50_000e18;
        uint256 usdtAmt = 60_000e18;

        // User 2 opens a vault
        _depositCollateralAndMintDsc(link, TEST_USER_2, linkAmt, linkAmt, dscAmt);

        // mint liquidator(user 1) dsc backed by usdt
        _depositCollateralAndMintDsc(collIds[3], TEST_USER_1, usdtAmt, usdtAmt, liquidatorDsc);

        // The vault is currently healthy.
        vm.expectRevert(DSCEngine.DSCEngine__VaultNotUnderwater.selector);
        vm.startPrank(TEST_USER_1);
        // Only marking and not liquidating.
        engine.markVaultAsUnderwater(link, TEST_USER_2, false, 0, false);
        vm.stopPrank();
    }

    function test_RevertWhenLiquidatorAttemptsLiquidationOfHealthyVault() public {
        bytes32 link = collIds[2];
        uint256 linkAmt = 1000e18;
        // 1000 link allows minting ~ 9212 dsc
        uint256 dscAmt = 8000e18;

        // liquidator opens a usdt vault to acquire dsc
        uint256 liquidatorDsc = 50_000e18;
        uint256 usdtAmt = 60_000e18;

        // User 2 opens a vault
        _depositCollateralAndMintDsc(link, TEST_USER_2, linkAmt, linkAmt, dscAmt);

        // mint liquidator(user 1) dsc backed by usdt
        _depositCollateralAndMintDsc(collIds[3], TEST_USER_1, usdtAmt, usdtAmt, liquidatorDsc);

        // The vault is currently healthy.
        vm.expectRevert(LM__VaultNotLiquidatable.selector);
        vm.startPrank(TEST_USER_1);
        // Attempting a liquidation
        engine.liquidateVault(link, TEST_USER_2, 10e18, false);
        vm.stopPrank();
    }

    function test_VaultCanBeMarkedAsUnderwaterWhenHFIsBelowMinimumHF() public {
        // vault owner - ETH
        uint256 ethAmt = 20 ether; // mints ~ 23721 dsc
        uint256 dscAmt = 23_000e18;

        // Liquidator
        uint256 liquidatorUsdtAmt = 60_000e18;
        uint256 liquidatorDscAmt = 50_000e18;

        // User 1 opens vault
        vm.startPrank(TEST_USER_1);
        engine.depositEtherCollateralAndMintDSC{value: ethAmt}(dscAmt);
        vm.stopPrank();

        // Obtain dsc for liquidator
        _depositCollateralAndMintDsc(collIds[3], TEST_USER_2, liquidatorUsdtAmt, liquidatorUsdtAmt, liquidatorDscAmt);

        // 24 hours later, ETH price drops down to $1800.02
        vm.warp(block.timestamp + 1 days);
        // eth uses weth price feed
        _mockPriceChange(collIds[1], 180002e6);

        // Now user 1's vault is undercollateralized and can be marked as underwater
        // Successful marking emits
        vm.expectEmit(true, true, false, false, address(engine));
        emit VaultMarkedAsUnderwater(collIds[0], TEST_USER_1);

        vm.startPrank(TEST_USER_2);
        engine.markVaultAsUnderwater(collIds[0], TEST_USER_1, false, 0, false);
        vm.stopPrank();
    }

    function test_RevertWhenLiquidatorAttemptsPartialVaultLiquidation() public {
        // weth vault
        bytes32 weth = collIds[1];
        uint256 wethAmt = 50 ether; // mints ~ 59304 dsc
        uint256 dscAmt = 59_000e18;

        // Liquidator opens a usdt vault to acquire dsc for liquidation
        address liquidator = makeAddr("Liquidator User");
        uint256 liquidatorUsdtAmt = 120_000e18;
        uint256 liquidatorDscAmt = 100_0000e18;

        // Acquire liquidator's dsc
        _depositCollateralAndMintDsc(collIds[3], liquidator, liquidatorUsdtAmt, liquidatorUsdtAmt, liquidatorDscAmt);

        // Open weth vault for user 1 that will be liquidated
        _depositCollateralAndMintDsc(weth, TEST_USER_1, wethAmt, wethAmt, dscAmt);

        // 7 days later, price of weth drops to $2000 rendering the position of user 1 liquidatable
        vm.warp(block.timestamp + 7 days);
        _mockPriceChange(weth, 2000e8);

        // Liquidator attempts to partially liquidate the position of 59k dsc with only 50k dsc
        vm.expectRevert(LM__SuppliedDscNotEnoughToRepayBadDebt.selector);
        vm.startPrank(liquidator);
        engine.markVaultAsUnderwater(weth, TEST_USER_1, true, 50_000e18, false);
        vm.stopPrank();
    }

    function _computeRewards(bytes32 collId, address owner, uint256 timeMarked) internal returns (uint256) {
        (, uint256 dscDebt) = engine.getVaultInformation(collId, owner);
        // discount based on speed of liquidation
        uint256 discountUsd = _timeDecayedDiscount(timeMarked, dscDebt);

        // additional reward based on debt size that depends on collateral's risk
        // eth, weth and link have an additional reward of 1.5% while usdt and dai has 0.5%
        // This additional reward is however bound between a minimum amount and a max reward
        uint256 rewardBasedOnSizeUsd = _rewardPerSize(collId, dscDebt);

        uint256 totalUsdRewards = discountUsd + rewardBasedOnSizeUsd;

        // rewards expressed in the backing vault collateral
        uint256 tokenRewards = engine.getTokenAmountFromUsdValue2(collId, totalUsdRewards);

        return tokenRewards;
    }

    function _timeDecayedDiscount(uint256 timeMarked, uint256 dscAmt) internal view returns (uint256) {
        uint256 startRate = 3e16; // 3%
        uint256 endRate = 18e15; // 1.8%
        uint256 rateDecayTime = 1 hours;
        uint256 currentRate;
        uint256 discount;
        uint256 timeElapsed = block.timestamp - timeMarked;

        if (timeElapsed == 0) {
            currentRate = startRate;
        } else if (timeElapsed > rateDecayTime) {
            currentRate = endRate;
        } else {
            currentRate = startRate - ((timeElapsed * (startRate - endRate)) / rateDecayTime);
        }
        // console.log("here12");
        // The below expression overflows, breaking down into chunks using temp variables.
        // currentRate = startRate - ((timeElapsed * (startRate - endRate)) / rateDecayTime);
        // uint256 temp1 = timeElapsed * (startRate - endRate);
        // uint256 temp2 = temp1 / rateDecayTime;
        // console.log("here13");
        // currentRate = startRate - temp2;
        // console.log("here14");
        discount = (currentRate * dscAmt) / 1e18;

        return discount;
    }

    function _rewardPerSize(bytes32 collId, uint256 dscAmt) internal view returns (uint256) {
        uint256 highRisk = 15e15; // 1.5% rate
        uint256 lowRisk = 5e15; // 0.5% rate
        uint256 rate;
        uint256 calculatedReward;
        uint256 minReward = 10e18; // 10 dsc
        uint256 maxReward = 5_000e18; // 5000 dsc

        if (collId == collIds[0] || collId == collIds[1] || collId == collIds[2]) {
            rate = highRisk;
        } else if (collId == collIds[3] || collId == collIds[4]) {
            rate = lowRisk;
        }

        calculatedReward = (rate * dscAmt) / 1e18; // scale down the multiplication
        // Should calculated reward be less than 10 dsc, take 10 dsc, otherwise take the calculated one
        // Also, only take the minimum of the above and 5000 dsc.
        return (_min(_max(calculatedReward, minReward), maxReward));
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a < b ? a : b);
    }

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a > b ? a : b);
    }

    function _preApprove(address owner, uint256 amount) internal {
        vm.startPrank(owner);
        ERC20Like(address(dsc)).approve(address(engine), amount);
        vm.stopPrank();
    }

    function test_LiquidatingWETHVaultCalculatesRewardsForLiquidatorProperly() public {
        // weth vault
        bytes32 weth = collIds[1];
        uint256 wethAmt = 50 ether; // mints ~ 59304 dsc
        uint256 dscAmt = 59_000e18;

        // Liquidator opens a usdt vault to acquire dsc for liquidation
        address liquidator = makeAddr("Liquidator User");
        address keeper = makeAddr("A different user who marks positions as unhealthy without liquidating them");
        uint256 liquidatorUsdtAmt = 120_000e6;
        uint256 liquidatorDscAmt = 100_000e18;

        uint256 underwaterTime;

        // Acquire liquidator's dsc
        _depositCollateralAndMintDsc(collIds[3], liquidator, liquidatorUsdtAmt, liquidatorUsdtAmt, liquidatorDscAmt);

        // Open weth vault for user 1 that will be liquidated
        _depositCollateralAndMintDsc(weth, TEST_USER_1, wethAmt, wethAmt, dscAmt);

        // 7 days later, price of weth drops to $2000 rendering the position of user 1 liquidatable
        vm.warp(block.timestamp + 7 days);
        _mockPriceChange(weth, 2000e8);

        uint256 liquidationAmt = 59_000e18;

        // Mark the vault as underwater, so it can be liquidated later.
        // In tests, separating the mark and liquidate steps makes it easier
        // to compare expected vs actual rewards, rather than doing both
        // in a single call to `markVaultAUnderwater()`with the liquidate
        // parameter being true.
        vm.startPrank(keeper);
        // Only add the vault to the list of unhealthy vaults but not liquidate.
        engine.markVaultAsUnderwater(weth, TEST_USER_1, false, 0, false);
        underwaterTime = block.timestamp;
        vm.stopPrank();

        // First approve engine to consume dsc
        _preApprove(liquidator, liquidationAmt);

        // Arrange - check the expected & actual rewards before vault is liquidated
        uint256 calculatedRewards = _computeRewards(weth, TEST_USER_1, underwaterTime);
        uint256 actualRewardsUsd = engine.calculateLiquidationRewards(weth, TEST_USER_1);
        uint256 actualRewards = engine.getTokenAmountFromUsdValue2(weth, actualRewardsUsd);

        vm.startPrank(liquidator);
        engine.markVaultAsUnderwater(weth, TEST_USER_1, true, liquidationAmt, false);
        vm.stopPrank();

        // Liquidator did not withdraw the liquidation outputs from protocol
        uint256 liquidatorWethBal = calculatedRewards + (engine.getTokenAmountFromUsdValue2(weth, liquidationAmt));

        assertEq(calculatedRewards, actualRewards);
        assertEq(engine.getUserCollateralBalance(weth, liquidator), liquidatorWethBal);
    }

    function test_LiquidatingLINKVaultCalculatesRewardsForLiquidatorProperly() public {
        // link vault
        bytes32 link = collIds[2];
        uint256 linkAmt = 1_000_000e18; // mints exactly 9_212_500 dsc
        uint256 dscAmt = 9_050_000e18;

        // Liquidator opens a usdt vault to acquire dsc for liquidation
        address liquidator = makeAddr("Liquidator User");
        address keeper = makeAddr("A different user who marks positions as unhealthy without liquidating them");
        uint256 liquidatorUsdtAmt = 12_000_000e6; // 12m usdt
        uint256 liquidatorDscAmt = 10_000_000e18; // 10m dsc

        uint256 underwaterTime;

        // Acquire liquidator's dsc
        _depositCollateralAndMintDsc(collIds[3], liquidator, liquidatorUsdtAmt, liquidatorUsdtAmt, liquidatorDscAmt);

        // Open link vault for user 1 that will be liquidated
        _depositCollateralAndMintDsc(link, TEST_USER_1, linkAmt, linkAmt, dscAmt);

        // 2 days later, price of link drops to $14.02 from $14.74 rendering the position of user 1 liquidatable
        vm.warp(block.timestamp + 2 days);
        _mockPriceChange(link, 1402e6);

        uint256 liquidationAmt = 9_050_000e18;

        // Mark the vault as underwater, so it can be liquidated later.
        // In tests, separating the mark and liquidate steps makes it easier
        // to compare expected vs actual rewards, rather than doing both
        // in a single call to `markVaultAUnderwater()` with the liquidate
        // parameter being true.
        vm.startPrank(keeper);
        // Only add the vault to the list of unhealthy vaults but not liquidate.
        engine.markVaultAsUnderwater(link, TEST_USER_1, false, 0, false);
        underwaterTime = block.timestamp;
        vm.stopPrank();

        // Simulate a 30-minute delay since the keeper marked the position.
        // As a result, the liquidator no longer qualifies for the 3% speedy execution discount.
        // Liquidator will get a rate between 3% and 1.8%
        vm.warp(block.timestamp + 30 minutes);

        // First approve engine to consume dsc
        _preApprove(liquidator, liquidationAmt);

        // Arrange - check the expected & actual rewards before vault is liquidated
        // Notice that 30 minutes have elapsed so far
        uint256 calculatedRewards = _computeRewards(link, TEST_USER_1, underwaterTime);
        uint256 actualRewardsUsd = engine.calculateLiquidationRewards(link, TEST_USER_1);
        uint256 actualRewards = engine.getTokenAmountFromUsdValue2(link, actualRewardsUsd);

        // Liquidator tries to mark and liquidate in a single call.
        // Since the keeper had already marked the vault as underwater earlier,
        // the discount is calculated from that original marking time — not the liquidation call.
        //
        // Liquidation math breakdown:
        // - Loan to cover: 9_050_000 dsc
        // - Base LINK collateral to receive = 9_050_000 / 14.02 = ~645_506.419401 LINK
        //
        // Discounts (Higher discounts for speedy liquidations of underwater positions):
        // Liquidation took place 30 minutes since vault became underwater, meaning a 2.4% as discount rate
        // Additional reward based on debt size; this is a high risk collateral vault hence a rate of 1.5%
        // But since this exceeds the upper limit of the reward based on size of 5_000 dsc, then the liquidator
        // will only get a max of 5_000 dsc instead of 135_750 dsc
        // - Time-based discount (30 minutes passed): 2.4% of 9_050_000 = 217_200 dsc
        // - Size-based reward (1.5% of 9_050_000 = 135_750 dsc), capped at 5_000 dsc
        //
        // Total reward in dsc: 217_200 + 5_000 = 222_200 dsc
        // Converted to LINK: 222_200 / 14.02 = ~15_848.7874465 LINK
        // In 18 decimals: 15_848.7874465 LINK = 15_848_787_446_504_992_867_332
        //
        // So the liquidator receives:
        // - 645_506.419401 LINK (base amount for covering the loan)
        // - +15_848.7874465 LINK (reward)
        // - = Total: ~661_355.2068475 LINK

        vm.startPrank(liquidator);
        engine.markVaultAsUnderwater(link, TEST_USER_1, true, liquidationAmt, false);
        vm.stopPrank();

        // Liquidator did not withdraw the liquidation outputs from protocol
        uint256 liquidatorWethBal = calculatedRewards + (engine.getTokenAmountFromUsdValue2(link, liquidationAmt));

        assertEq(calculatedRewards, actualRewards);
        assertEq(engine.getUserCollateralBalance(link, liquidator), liquidatorWethBal);
    }

    function test_LiquidatingDAIVaultCalculatesRewardsForLiquidatorProperly() public {
        // weth vault
        bytes32 dai = collIds[4];
        uint256 daiAmt = 3_575_000e18; // mints exactly  3.25m dsc
        uint256 dscAmt = 3_250_000e18;

        // Liquidator opens a usdt vault to acquire dsc for liquidation
        address liquidator = makeAddr("Liquidator User");
        address keeper = makeAddr("A different user who marks positions as unhealthy without liquidating them");
        uint256 liquidatorUsdtAmt = 6_000_000e6; // 6m usdt
        uint256 liquidatorDscAmt = 5_000_000e18; // 5m dsc

        uint256 underwaterTime;

        // Acquire liquidator's dsc
        _depositCollateralAndMintDsc(collIds[3], liquidator, liquidatorUsdtAmt, liquidatorUsdtAmt, liquidatorDscAmt);

        // Open dai vault for user 1 that will be liquidated
        _depositCollateralAndMintDsc(dai, TEST_USER_1, daiAmt, daiAmt, dscAmt);

        // 4 months (4*30*1 days) later, price of dai drops to $0.9987 from $1.0001 rendering the position of user 1
        // liquidatable
        vm.warp(block.timestamp + 120 days);
        _mockPriceChange(dai, 9987e4);

        uint256 liquidationAmt = 3_250_000e18;

        // Mark the vault as underwater, so it can be liquidated later.
        // In tests, separating the mark and liquidate steps makes it easier
        // to compare expected vs actual rewards, rather than doing both
        // in a single call to `markVaultAUnderwater()` with the liquidate
        // parameter being true.
        vm.startPrank(keeper);
        // Only add the vault to the list of unhealthy vaults but not liquidate.
        engine.markVaultAsUnderwater(dai, TEST_USER_1, false, 0, false);
        underwaterTime = block.timestamp;
        vm.stopPrank();

        // Simulate a 2-hour delay since the keeper marked the position.
        // As a result, the liquidator no longer qualifies for the 3% speedy execution discount.
        // Liquidator will get a rate of 1.8% since 1 hours has elapsed since vault became underwater.
        vm.warp(block.timestamp + 2 hours);

        // First approve engine to consume dsc
        _preApprove(liquidator, liquidationAmt);

        // Arrange - check the expected & actual rewards before vault is liquidated
        // Notice that 2 hours have elapsed so far
        uint256 calculatedRewards = _computeRewards(dai, TEST_USER_1, underwaterTime);
        uint256 actualRewardsUsd = engine.calculateLiquidationRewards(dai, TEST_USER_1);
        uint256 actualRewards = engine.getTokenAmountFromUsdValue2(dai, actualRewardsUsd);

        // Liquidator tries to mark and liquidate in a single call.
        // Since the keeper had already marked the vault as underwater earlier,
        // the discount is calculated from that original marking time — not the liquidation call.
        //
        // Liquidation math breakdown:
        // - Loan to cover: 3_250_000 dsc
        // - Base DAI collateral to receive = 3_250_000 / 0.9987 = ~3_254_230.49965
        //
        // Discounts (Higher discounts for speedy liquidations of underwater positions):
        // Liquidation took place 2 hours since vault became underwater, meaning a 1.8% as discount rate
        // Additional reward based on debt size; this is a low risk collateral vault hence a rate of 0.5%
        // But since this exceeds the upper limit of the reward based on size of 5_000 dsc, then the liquidator
        // will only get a max of 5_000 dsc instead of 16_250 dsc
        // - Time-based discount (2 hours  passed): 1.8% of 3_250_000 = 58_500 dsc
        // - Size-based reward (0.5% of 3_250_000 = 16_250 dsc), capped at 5_000 dsc
        //
        // Total reward in dsc: 58_500 + 5_000 = 63_500 dsc
        // Converted to DAI: 63_500 / 0.9987 = ~63_582.6574547 DAI
        // In 18 decimals: 63_582.6574547 DAI = 63582.657454691098427956
        //
        // So the liquidator receives:
        // - 3_254_230.49965 DAI (base amount for covering the loan)
        // - +63_582.6574547 DAI(reward)
        // - = Total: ~3_317_813.1571 DAI

        vm.startPrank(liquidator);
        engine.markVaultAsUnderwater(dai, TEST_USER_1, true, liquidationAmt, false);
        vm.stopPrank();

        // Liquidator did not withdraw the liquidation outputs from protocol
        uint256 liquidatorWethBal = calculatedRewards + (engine.getTokenAmountFromUsdValue2(dai, liquidationAmt));

        assertEq(calculatedRewards, actualRewards);
        assertEq(engine.getUserCollateralBalance(dai, liquidator), liquidatorWethBal);
    }

    function test_LiquidatingUSDTVaultCalculatesRewardsForLiquidatorProperlyAndEmits() public {
        // weth vault
        bytes32 usdt = collIds[3];
        uint256 usdtAmt = 3_900_000e6; // mints exactly  3.25m dsc
        uint256 dscAmt = 3_250_000e18;

        // Liquidator opens a usdt vault to acquire dsc for liquidation
        address liquidator = makeAddr("Liquidator User");
        address keeper = makeAddr("A different user who marks positions as unhealthy without liquidating them");
        uint256 liquidatorUsdtAmt = 6_000_000e6; // 6m usdt
        uint256 liquidatorDscAmt = 5_000_000e18; // 5m dsc

        uint256 underwaterTime;

        // Acquire liquidator's dsc
        _depositCollateralAndMintDsc(collIds[3], liquidator, liquidatorUsdtAmt, liquidatorUsdtAmt, liquidatorDscAmt);

        // Open usdt vault for user 1 that will be liquidated
        _depositCollateralAndMintDsc(usdt, TEST_USER_1, usdtAmt, usdtAmt, dscAmt);

        // 2 weeks later, price of usdt drops to $0.9991 from $1.0001 rendering the position of user 1
        // liquidatable
        vm.warp(block.timestamp + 2 weeks);
        _mockPriceChange(usdt, 9991e14);

        uint256 liquidationAmt = 3_250_000e18;

        // Mark the vault as underwater, so it can be liquidated later.
        // In tests, separating the mark and liquidate steps makes it easier
        // to compare expected vs actual rewards, rather than doing both
        // in a single call to `markVaultAUnderwater()` with the liquidate
        // parameter being true.
        vm.startPrank(keeper);
        // Only add the vault to the list of unhealthy vaults but not liquidate.
        engine.markVaultAsUnderwater(usdt, TEST_USER_1, false, 0, false);
        underwaterTime = block.timestamp;
        vm.stopPrank();

        // Simulate a 43-minute delay since the keeper marked the position.
        // As a result, the liquidator no longer qualifies for the 3% speedy execution discount.
        // Liquidator will get a rate between 3% and 1.8%.
        vm.warp(block.timestamp + 43 minutes);

        // First approve engine to consume dsc
        _preApprove(liquidator, liquidationAmt);

        // Arrange - check the expected & actual rewards before vault is liquidated
        // Notice that 43 minutes have elapsed so far
        uint256 calculatedRewards = _computeRewards(usdt, TEST_USER_1, underwaterTime);
        uint256 actualRewardsUsd = engine.calculateLiquidationRewards(usdt, TEST_USER_1);
        uint256 actualRewards = engine.getTokenAmountFromUsdValue2(usdt, actualRewardsUsd);

        // Liquidator tries to mark and liquidate in a single call.
        // Since the keeper had already marked the vault as underwater earlier,
        // the discount is calculated from that original marking time — not the liquidation call.
        //
        // Liquidation math breakdown:
        // - Loan to cover: 3_250_000 dsc
        // - Base USDT collateral to receive = 3_250_000 / 0.9991 = ~3_252_927.63487
        //
        // Discounts (Higher discounts for speedy liquidations of underwater positions):
        // Liquidation took place 43 minutes since vault became underwater, meaning a 2.14% as discount rate
        // Additional reward based on debt size; this is a low risk collateral vault hence a rate of 0.5%
        // But since this exceeds the upper limit of the reward based on size of 5_000 dsc, then the liquidator
        // will only get a max of 5_000 dsc instead of 16_250 dsc
        // - Time-based discount (43 minutes passed): 2.14% of 3_250_000 = 69_550 dsc
        // - Size-based reward (0.5% of 3_250_000 = 16_250 dsc), capped at 5_000 dsc
        //
        // Total reward in dsc: 69_550 + 5_000 = 74_550 dsc
        // Converted to USDT: 74_550 / 0.9991 = ~74_617.1554399 USDT
        // In 6 decimals as used by USDT: 74_617.1554399 USDT = 74617.155439
        //
        // So the liquidator receives:
        // - 3_252_927.63487 USDT (base amount for covering the loan)
        // - +74_617.155439 USDT(reward)
        // - = Total: ~3_327_544.79031 USDT

        // This liquidation involves full rewards to liquidator
        vm.expectEmit(true, true, false, true, address(engine));
        emit LiquidationWithFullRewards(usdt, TEST_USER_1, liquidator);

        vm.startPrank(liquidator);
        engine.markVaultAsUnderwater(usdt, TEST_USER_1, true, liquidationAmt, false);
        vm.stopPrank();

        // Liquidator did not withdraw the liquidation outputs from protocol
        uint256 liquidatorWethBal = calculatedRewards + (engine.getTokenAmountFromUsdValue2(usdt, liquidationAmt));

        assertEq(calculatedRewards, actualRewards);
        assertEq(engine.getUserCollateralBalance(usdt, liquidator), liquidatorWethBal);
    }

    function test_LiquidatingLINKVaultWithPartialRewardsEmits() public {
        // link vault
        bytes32 link = collIds[2];
        uint256 linkAmt = 1_000_000e18; // mints exactly 9_212_500 dsc
        uint256 dscAmt = 9_050_000e18;

        // Liquidator opens a usdt vault to acquire dsc for liquidation
        address liquidator = makeAddr("Liquidator User");
        address keeper = makeAddr("A different user who marks positions as unhealthy without liquidating them");
        uint256 liquidatorUsdtAmt = 12_000_000e6; // 12m usdt
        uint256 liquidatorDscAmt = 10_000_000e18; // 10m dsc

        uint256 underwaterTime;

        // Acquire liquidator's dsc
        _depositCollateralAndMintDsc(collIds[3], liquidator, liquidatorUsdtAmt, liquidatorUsdtAmt, liquidatorDscAmt);

        // Open link vault for user 1 that will be liquidated
        _depositCollateralAndMintDsc(link, TEST_USER_1, linkAmt, linkAmt, dscAmt);

        // 2 days later, price of link drops to $9.06 from $14.74 rendering the position of user 1 liquidatable
        vm.warp(block.timestamp + 2 days);
        _mockPriceChange(link, 916e6);

        // Mark the vault as underwater, so it can be liquidated later.
        // In tests, separating the mark and liquidate steps makes it easier
        // to compare expected vs actual rewards, rather than doing both
        // in a single call to `markVaultAUnderwater()` with the liquidate
        // parameter being true.
        vm.startPrank(keeper);
        // Only add the vault to the list of unhealthy vaults but not liquidate.
        engine.markVaultAsUnderwater(link, TEST_USER_1, false, 0, false);
        underwaterTime = block.timestamp;
        vm.stopPrank();

        // Simulate a 5-minute delay since the keeper marked the position.
        // As a result, the liquidator no longer qualifies for the 3% speedy execution discount.
        // Liquidator will get a rate between 3% and 1.8% but close to 3% as only 5 minutes have elapsed.
        vm.warp(block.timestamp + 5 minutes);

        // First approve engine to consume dsc
        _preApprove(liquidator, dscAmt);

        // Arrange - check the expected & actual rewards before vault is liquidated
        // Notice that 5 minutes have elapsed so far
        uint256 calculatedRewards = _computeRewards(link, TEST_USER_1, underwaterTime);
        uint256 actualRewards =
            engine.getTokenAmountFromUsdValue2(link, (engine.calculateLiquidationRewards(link, TEST_USER_1)));

        // Liquidator tries to mark and liquidate in a single call.
        // Since the keeper had already marked the vault as underwater earlier,
        // the discount is calculated from that original marking time — not the liquidation call.
        //
        // Liquidation math breakdown:
        // - Loan to cover: 9_050_000 dsc
        // - Base LINK collateral to receive = 9_050_000 / 9.06 = ~998_896.247241 LINK
        //
        // Discounts (Higher discounts for speedy liquidations of underwater positions):
        // Liquidation took place 5 minutes since vault became underwater, meaning a 2.9% as discount rate
        // Additional reward based on debt size; this is a high risk collateral vault hence a rate of 1.5%
        // But since this exceeds the upper limit of the reward based on size of 5_000 dsc, then the liquidator
        // will only get a max of 5_000 dsc instead of 135_750 dsc
        // - Time-based discount (30 minutes passed): 2.9% of 9_050_000 = 262_450 dsc
        // - Size-based reward (1.5% of 9_050_000 = 135_750 dsc), capped at 5_000 dsc
        //
        // Total reward in dsc: 262_450 + 5_000 = 267_450 dsc
        // Converted to LINK: 267_450 / 9.06 = ~29_519.8675497 LINK
        // In 18 decimals: 29_519.8675497 LINK = 29197.598253275109170305
        //
        // So what the liquidator should receive is:
        // - 998_896.247241 LINK (base amount for covering the loan)
        // - +29_519.8675497 LINK (reward)
        // - = Total: ~ 1_028_416.11479 LINK
        // However, only 1_000_000 LINK is locked in this vault and it is also from the 1m LINK
        // where fees are deducted from and liquidation penalty.
        // Fees for 2 days 5 minutes as calculated below is 54.230494739220886256 LINK
        // Liquidation penalty as calculated below is: 9879.912663755458515283 LINK
        // Thus the actual output that liquidator gets is not 1_028_416.11479 LINK but rather
        // = 1 million vault LINK - 54.230494739220886256 LINK - 9879.912663755458515283 LINK
        // = 990065.856841505320598461 LINK

        vm.expectEmit(true, true, false, true, address(engine));
        emit LiquidationWithPartialRewards(link, TEST_USER_1, liquidator);

        vm.startPrank(liquidator);
        engine.markVaultAsUnderwater(link, TEST_USER_1, true, dscAmt, false);
        vm.stopPrank();

        // Liquidator did not withdraw the liquidation outputs from protocol
        // But got all the remainder after fees and liquidation penalty was taken from the 1m LINK
        // 1% liquidation penalty
        uint256 penaltyInLINK = engine.getTokenAmountFromUsdValue2(link, ((dscAmt * 1e16) / 1e18));

        // Fees for having the vault for 2 days and 5 minutes - 2885 minutes
        // APR is 1% annual fee
        // fee formula = (debt * APR * deltaTime) / (SECONDS_IN_YEAR * PRECISION);
        uint256 feesInLINK =
            engine.getTokenAmountFromUsdValue2(link, ((dscAmt * 1e16 * 2885 minutes) / (365 days * 1e18)));

        assertEq(engine.getUserCollateralBalance(link, liquidator), (linkAmt - penaltyInLINK - feesInLINK));
        assertEq(calculatedRewards, actualRewards);
        console.log("calc", calculatedRewards);
    }

    function test_LiquidationOfDeeplyUnderwaterVaultTriggersBadDebtAbsorptionByProtocolAndEmits() public {
        // link vault
        bytes32 link = collIds[2];
        uint256 linkAmt = 1_000_000e18; // mints exactly 9_212_500 dsc
        uint256 dscAmt = 9_050_000e18;

        // Liquidator opens a usdt vault to acquire dsc for liquidation
        address liquidator = makeAddr("Liquidator User");
        address keeper = makeAddr("A different user who marks positions as unhealthy without liquidating them");
        uint256 liquidatorUsdtAmt = 12_000_000e6; // 12m usdt
        uint256 liquidatorDscAmt = 10_000_000e18; // 10m dsc

        uint256 underwaterTime;

        // Acquire liquidator's dsc
        _depositCollateralAndMintDsc(collIds[3], liquidator, liquidatorUsdtAmt, liquidatorUsdtAmt, liquidatorDscAmt);

        // Open link vault for user 1 that will be liquidated
        _depositCollateralAndMintDsc(link, TEST_USER_1, linkAmt, linkAmt, dscAmt);

        // 90 days later, price of link drops to $4.06 from $14.74 rendering the position of user 1 liquidatable
        /// and deeply undercollateralized.
        vm.warp(block.timestamp + 90 days);
        _mockPriceChange(link, 406e6);

        // Mark the vault as underwater, so it can be liquidated later.
        // In tests, separating the mark and liquidate steps makes it easier
        // to compare expected vs actual rewards, rather than doing both
        // in a single call to `markVaultAUnderwater()` with the liquidate
        // parameter being true.
        vm.startPrank(keeper);
        // Only add the vault to the list of unhealthy vaults but not liquidate.
        engine.markVaultAsUnderwater(link, TEST_USER_1, false, 0, false);
        underwaterTime = block.timestamp;
        vm.stopPrank();

        // Simulate a 16-minute delay since the keeper marked the position.
        // As a result, the liquidator no longer qualifies for the 3% speedy execution discount.
        // Liquidator will get a rate between 3% and 1.8%.
        vm.warp(block.timestamp + 16 minutes);

        // First approve engine to consume dsc
        _preApprove(liquidator, dscAmt);

        // Arrange - check the expected & actual rewards before vault is liquidated
        // Notice that 16 minutes have elapsed so far
        uint256 calculatedRewards = _computeRewards(link, TEST_USER_1, underwaterTime);
        uint256 liquidatorDscBefore = ERC20Like(address(dsc)).balanceOf(liquidator);

        // Liquidator tries to mark and liquidate in a single call.
        // Since the keeper had already marked the vault as underwater earlier,
        // the discount is calculated from that original marking time — not the liquidation call.
        //
        // Liquidation math breakdown:
        // - Loan to cover: 9_050_000 dsc
        // - Base LINK collateral to receive = 9_050_000 / 9.06 = ~2_229_064.03941 LINK
        // - Notice that the base collateral that liquidator should get already exceeds the  locked collateral balance
        // of 1_000_000 LINK. This means that this liquidation will not yield any rewards/outputs to liquidator and thus
        // the protocol will absorb it as a bad debt.
        //
        // Discounts (Higher discounts for speedy liquidations of underwater positions):
        // Liquidation took place 16 minutes since vault became underwater, meaning a 2.68% as discount rate
        // Additional reward based on debt size; this is a high risk collateral vault hence a rate of 1.5%
        // But since this exceeds the upper limit of the reward based on size of 5_000 dsc, then the liquidator
        // will only get a max of 5_000 dsc instead of 135_750 dsc
        // - Time-based discount (16 minutes passed): 2.68% of 9_050_000 = 242_540 dsc
        // - Size-based reward (1.5% of 9_050_000 = 135_750 dsc), capped at 5_000 dsc
        //
        // Total reward in dsc: 242_540 + 5_000 = 247_540 dsc
        // Converted to LINK: 267_450 / 4.06 = ~60_970.4433497 LINK
        // In 18 decimals: 60_970.4433497 LINK =
        //
        // So what the liquidator should receive is:
        // - 2_229_064.03941 LINK (base amount for covering the loan)
        // - +60_970.4433497 LINK (reward)
        // - = Total: ~ 2_290_034.48276 LINK
        // However, only 1_000_000 LINK is locked in this vault and it is also from the 1m LINK
        // where fees are deducted from and liquidation penalty.
        // Since the output of liquidation is greater than the locked collateral and also the base pay is greater than
        // 1m LINK that is currently locked in this vault, then this liquidation results to the vault being absorbed
        // as bad debt.

        vm.expectEmit(true, true, false, false, address(engine));
        emit AbsorbedBadDebt(link, TEST_USER_1);

        vm.startPrank(liquidator);
        engine.markVaultAsUnderwater(link, TEST_USER_1, true, dscAmt, false);
        vm.stopPrank();

        uint256 expectedOutput = calculatedRewards + (engine.getTokenAmountFromUsdValue2(link, dscAmt));
        uint256 liquidatorDscAfter = ERC20Like(address(dsc)).balanceOf(liquidator);

        assertGt(expectedOutput, linkAmt);
        assertEq(liquidatorDscBefore, liquidatorDscAfter);
    }

}

contract Dummy {

    uint8 num;

    constructor() {
        num = 10;
    }

}
