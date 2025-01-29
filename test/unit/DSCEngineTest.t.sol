// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {IERC20Errors} from "@openzeppelin/contracts@5.1.0/interfaces/draft-IERC6093.sol";
import {ERC20Mock} from "@openzeppelin/contracts@5.1.0/mocks/token/ERC20Mock.sol";
import {AggregatorV3Interface} from "@chainlink/contracts@v1.3.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    DeployDSC deployer;
    HelperConfig config;
    address wETH;
    address wBTC;
    address wETHUsdPriceFeed;
    address wBTCUsdPriceFeed;

    address TEST_USER_1 = makeAddr("Test_User_1");
    address TEST_USER_2 = makeAddr("Test_User_2");
    uint256 private constant STARTING_BALANCE = 1000 ether;

    uint256 private constant PRECISION = 1e18;
    uint256 private constant PRECISION_SCALE = 1e10;

    uint256 private constant LOCAL_ANVIL_CHAIN_ID = 31337;

    address[] public tokens;
    address[] public priceFeeds;

    uint256 private constant MAX_APPROVAL = type(uint256).max;

    uint256 private constant wETH_DEPOSIT_AMOUNT = 10 ether;
    uint256 private constant wBTC_DEPOSIT_AMOUNT = 10 ether;

    int256 private constant NEW_PRICE = 56_000e8;

    uint256 private constant LIQUIDATION_COLLATERAL = 2_000e18;
    uint256 private constant LIQUIDATION_DSC = 1_000e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant LIQUIDATION_PRECISION = 100;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (wETH, wBTC, wETHUsdPriceFeed, wBTCUsdPriceFeed, ) = config
            .activeChainNetworkConfig();
        vm.deal(TEST_USER_1, STARTING_BALANCE);
        vm.deal(TEST_USER_2, STARTING_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    function test_RevertWhen_DSCEngineDeploymentWithUnequalTokenAndPriceFeedAddressesLengths()
        public
    {
        // 1 token but 2 price feeds
        tokens = [wETH];
        priceFeeds = [wETHUsdPriceFeed, wBTCUsdPriceFeed];

        vm.expectRevert(
            DSCEngine
                .DSCEngine__CollateralTokensAddressesAndPriceFeedsAddressesLengthMismatch
                .selector
        );

        vm.startBroadcast();
        new DSCEngine(tokens, priceFeeds, address(dsc));
        vm.stopBroadcast();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/
    function test_RevertWhen_AmountToDepositAsCollateralIsZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__ZeroAmountNotAllowed.selector);

        vm.startPrank(TEST_USER_1);
        dscEngine.depositCollateral(wETH, 0);
        vm.stopPrank();
    }

    function test_RevertWhen_TokenToDepositAsCollateralIsNotSupported() public {
        vm.expectRevert(
            DSCEngine.DSCEngine__CollateralTokenNotAllowed.selector
        );

        vm.startPrank(TEST_USER_1);
        /// Token with address 456 is not approved as a collateral token.
        dscEngine.depositCollateral(address(456), 10);
        vm.stopPrank();
    }

    modifier hasBalance(address user) {
        ERC20Mock(wETH).mint(user, STARTING_BALANCE);
        ERC20Mock(wBTC).mint(user, STARTING_BALANCE);
        _;
    }

    modifier skipTestWhenForking() {
        if (block.chainid != LOCAL_ANVIL_CHAIN_ID) {
            return;
        }
        _;
    }

    modifier approvalDone(address approver) {
        vm.startPrank(approver);
        ERC20Mock(wETH).approve(address(dscEngine), MAX_APPROVAL);
        ERC20Mock(wBTC).approve(address(dscEngine), MAX_APPROVAL);
        vm.stopPrank();
        _;
    }

    function test_RevertWhen_UserDepositsCollateralWithoutApprovingDSCEngineToSpendTheirTokens()
        public
        skipTestWhenForking
    {
        vm.expectPartialRevert(
            IERC20Errors.ERC20InsufficientAllowance.selector
        );

        vm.startPrank(TEST_USER_1);
        dscEngine.depositCollateral(wETH, 3);
        vm.stopPrank();
    }

    function test_SuccessfulDepositOfCollateralEmitsEvent()
        public
        skipTestWhenForking
        hasBalance(TEST_USER_1)
    {
        uint256 amountToDeposit = 123e18;

        vm.startPrank(TEST_USER_1);
        ERC20Mock(wETH).approve(address(dscEngine), amountToDeposit);

        vm.expectEmit(address(dscEngine));
        emit DSCEngine.CollateralDeposited(TEST_USER_1, wETH, amountToDeposit);

        dscEngine.depositCollateral(wETH, amountToDeposit);
        vm.stopPrank();
    }

    function test_SuccessfulDepositIncrementsAccountCollateral()
        public
        hasBalance(TEST_USER_2)
        approvalDone(TEST_USER_2)
    {
        // Arrange act assert
        // deposit 10 wBTC
        uint256 depositAmount = 10 ether;

        vm.startPrank(TEST_USER_2);
        dscEngine.depositCollateral(wBTC, depositAmount);
        vm.stopPrank();

        uint256 expectedwBTCCollateral = dscEngine.getAccountCollateral(
            wBTC,
            TEST_USER_2
        );

        assertEq(expectedwBTCCollateral, depositAmount);
    }

    function test_depositCollateralAndMintDSCMintsDSCAndStoresUserCollateral()
        public
        hasBalance(TEST_USER_1)
        approvalDone(TEST_USER_1)
    {
        uint256 wETHDepositAmt = 10 ether;
        // Can mint DSC worth half the value of my deposit.
        uint256 depositValue = dscEngine.getValueInUSD(wETH, wETHDepositAmt);
        uint256 mintableDSC = depositValue / 2; // Max of allowable DSC for the collateral.

        vm.startPrank(TEST_USER_1);
        dscEngine.depositCollateralAndMintDSC(
            wETH,
            wETHDepositAmt,
            mintableDSC
        );
        vm.stopPrank();

        assertTrue(
            dscEngine.getAccountCollateral(wETH, TEST_USER_1) == wETHDepositAmt
        );

        (uint256 dscBal, ) = dscEngine.getAccountInformation(TEST_USER_1);
        assertEq(dscBal, mintableDSC);
    }

    function test_RevertWhen_depositCollateralAndMintZeroDSCAmount()
        public
        hasBalance(TEST_USER_2)
        approvalDone(TEST_USER_2)
    {
        uint256 wETHDepositAmt = 10 ether;

        vm.expectRevert(DSCEngine.DSCEngine__ZeroAmountNotAllowed.selector);
        vm.startPrank(TEST_USER_2);
        dscEngine.depositCollateralAndMintDSC(wETH, wETHDepositAmt, 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              PRICE FEEDS
    //////////////////////////////////////////////////////////////*/
    function test_GetValueInUSDCorrectlyCalculatesTokensValue() public view {
        uint256 wETHAmount = 22 ether;

        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            wETHUsdPriceFeed
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        /// 22 ether  = 22 * 3383 = 74426 USD
        /// For precision sake to be compatible with the DSC token, the value in USD is
        /// having 18 decimals.
        uint256 expectedValue = (wETHAmount *
            (uint256(price) * PRECISION_SCALE)) / PRECISION;

        uint256 calculatedValue = dscEngine.getValueInUSD(wETH, wETHAmount);

        assertTrue(calculatedValue == expectedValue);
    }

    function test_getCollateralTokenAmountFromUsdValueCorrectlyCalculatesTokensAmount()
        public
        view
    {
        uint256 wETHUsdValue = 450 ether; // 18 decimals of USD value
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            wETHUsdPriceFeed
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 expectedwETHAmount = (wETHUsdValue * PRECISION) /
            (uint256(price) * PRECISION_SCALE);

        uint256 calculatedwETHAmount = dscEngine.getTokenAmountFromUSDValue(
            wETH,
            wETHUsdValue
        );

        console.log("Expected ", expectedwETHAmount);
        console.log("Calculated ", calculatedwETHAmount);

        assertTrue(calculatedwETHAmount == expectedwETHAmount);
    }

    /*//////////////////////////////////////////////////////////////
                              HEALTH TESTS
    //////////////////////////////////////////////////////////////*/
    function test_HealthFactorIsCorrectlyCalculated()
        public
        hasBalance(TEST_USER_1)
        approvalDone(TEST_USER_1)
        wBTCDepositAndMintDSC(TEST_USER_1)
    {
        // The wBTC deposit and minting of DSC is set to result to a health factor of 1.
        // This is because the DSC minted is half the value of the collateral deposited.
        uint256 expectedFactor = 1e18;
        uint256 calculatedFactor = dscEngine.getHealthFactor(TEST_USER_1);

        assertTrue(calculatedFactor == expectedFactor);
    }

    /*//////////////////////////////////////////////////////////////
                            REDEEMING TESTS
    //////////////////////////////////////////////////////////////*/
    modifier wETHDepositAndMintDSC(address depositor) {
        vm.startPrank(depositor);
        uint256 mintableDSC = dscEngine.getValueInUSD(
            wETH,
            wETH_DEPOSIT_AMOUNT
        ) / 2;
        dscEngine.depositCollateralAndMintDSC(
            wETH,
            wETH_DEPOSIT_AMOUNT,
            mintableDSC
        );
        vm.stopPrank();
        _;
    }

    modifier wBTCDepositAndMintDSC(address depositor) {
        vm.startPrank(depositor);
        uint256 mintableDSC = dscEngine.getValueInUSD(
            wBTC,
            wBTC_DEPOSIT_AMOUNT
        ) / 2;
        dscEngine.depositCollateralAndMintDSC(
            wBTC,
            wBTC_DEPOSIT_AMOUNT,
            mintableDSC
        );
        vm.stopPrank();
        _;
    }

    function test_redeemableCollateralHasToBeTwiceInValueAsDSCValue()
        public
        hasBalance(TEST_USER_1)
        approvalDone(TEST_USER_1)
        wETHDepositAndMintDSC(TEST_USER_1)
    {
        /// Attempting to redeem all collateral and burn all DSC.
        /// This test resulted in the discovery of a bug that restricted users from
        /// redeeming all their collateral and burning all their DSC.
        uint256 collateralValue = dscEngine.getValueInUSD(
            wETH,
            wETH_DEPOSIT_AMOUNT
        );
        uint256 collateralAmount = dscEngine.getTokenAmountFromUSDValue(
            wETH,
            collateralValue
        );
        uint256 burnableDSC = collateralValue / 2;

        vm.startPrank(TEST_USER_1);
        dsc.approve(address(dscEngine), MAX_APPROVAL);
        dscEngine.redeemCollateralForDSC(wETH, collateralAmount, burnableDSC);
        vm.stopPrank();
    }

    function test_RevertWhen_RedeemingMoreCollateralAndBurningLessDSC()
        public
        hasBalance(TEST_USER_2)
        approvalDone(TEST_USER_2)
        wETHDepositAndMintDSC(TEST_USER_2)
    {
        // Redeem all collateral but burn only 10% collateral value as DSC.
        uint256 allCollateralAmount = dscEngine.getAccountCollateral(
            wETH,
            TEST_USER_2
        );

        // 10 percent value of the collateral.
        uint256 tenthCollateralValue = (
            dscEngine.getValueInUSD(wETH, allCollateralAmount)
        ) / 10;

        vm.startPrank(TEST_USER_2);
        dsc.approve(address(dscEngine), MAX_APPROVAL);

        vm.expectPartialRevert(
            DSCEngine.DSCEngine__HealthFactorBelowThreshold.selector
        );

        dscEngine.redeemCollateralForDSC(
            wETH,
            allCollateralAmount,
            tenthCollateralValue
        );
        vm.stopPrank();
    }

    function test_RevertWhen_RedeemingCollateralForDSCWithZeroDSCAmount()
        public
        hasBalance(TEST_USER_1)
        approvalDone(TEST_USER_1)
        wBTCDepositAndMintDSC(TEST_USER_1)
    {
        uint256 allwBTC = dscEngine.getAccountCollateral(wBTC, TEST_USER_1);

        vm.startPrank(TEST_USER_1);
        dsc.approve(address(dscEngine), MAX_APPROVAL);

        vm.expectPartialRevert(
            DSCEngine.DSCEngine__ZeroAmountNotAllowed.selector
        );

        dscEngine.redeemCollateralForDSC(wBTC, allwBTC, 0);
    }

    function test_RedeemingCollateralEmitsRedeemEvent()
        public
        hasBalance(TEST_USER_2)
        approvalDone(TEST_USER_2)
        wBTCDepositAndMintDSC(TEST_USER_2)
    {
        uint256 wBTCBal = dscEngine.getAccountCollateral(wBTC, TEST_USER_2);
        // Redeem half collateral => 1/4 DSC of the collateral value.
        uint256 wBTCToRedeem = wBTCBal / 2;
        uint256 dscToBurn = (dscEngine.getValueInUSD(wBTC, wBTCBal)) / 4;

        vm.startPrank(TEST_USER_2);
        dsc.approve(address(dscEngine), MAX_APPROVAL);

        vm.recordLogs();
        dscEngine.redeemCollateralForDSC(wBTC, wBTCToRedeem, dscToBurn);
        vm.stopPrank();

        Vm.Log[] memory emittedEvents = vm.getRecordedLogs();

        // The expected event is the second last event in the logs because the last
        // event is the ERC20 Transfer event.
        // stored as a keccak256 hash of the event signature at topic 0.

        assertEq(
            emittedEvents[emittedEvents.length - 2].topics[0],
            keccak256("CollateralRedeemed(address,address,address,uint256)")
        );
    }

    /*//////////////////////////////////////////////////////////////
                           LIQUIDATION TESTS
    //////////////////////////////////////////////////////////////*/
    // Modifier for liquidations
    // 2 users where one will be the one to get liquidated and the other will be the liquidator.
    // Both needs to be active protocol users who are valid.

    modifier twoProtocolUsers() {
        address[2] memory testUsers = [TEST_USER_1, TEST_USER_2];
        for (uint8 k = 0; k < 2; k++) {
            vm.startPrank(testUsers[k]);
            // Mint collateral tokens for the users.
            ERC20Mock(wETH).mint(testUsers[k], STARTING_BALANCE);
            ERC20Mock(wBTC).mint(testUsers[k], STARTING_BALANCE);

            // Approve DSCEngine to spend the tokens.
            ERC20Mock(wETH).approve(address(dscEngine), MAX_APPROVAL);
            ERC20Mock(wBTC).approve(address(dscEngine), MAX_APPROVAL);

            // Deposit collateral and mint DSC for the users.
            // both collateral are deposited for the purposes of testing although
            // not all tokens are used at the same time.

            // How much DSC can be minted for each of the collateral - wETH and wBTC.
            uint256 wETH_DSC = dscEngine.getValueInUSD(
                wETH,
                wETH_DEPOSIT_AMOUNT
            ) / 2;

            uint256 wBTC_DSC = dscEngine.getValueInUSD(
                wBTC,
                wBTC_DEPOSIT_AMOUNT
            ) / 2;

            // Deposit collateral and mint DSC for the users.
            dscEngine.depositCollateralAndMintDSC(
                wETH,
                wETH_DEPOSIT_AMOUNT,
                wETH_DSC
            );

            dscEngine.depositCollateralAndMintDSC(
                wBTC,
                wBTC_DEPOSIT_AMOUNT,
                wBTC_DSC
            );

            vm.stopPrank();
        }
        _;
    }

    modifier liquidatable(address account) {
        address liquidator;
        if (account == TEST_USER_1) {
            liquidator = TEST_USER_2;
        } else {
            liquidator = TEST_USER_1;
        }
        /**
         * We can force liquidation by dipping the price of wBTC to $10.
         * This will make the health factor of the account to be less than 1 since
         * wBTC collateral token of a user holds more value than the wETH token.
         */
        uint256 liquidatorCollateralValueBefore = dscEngine
            .getAccountCollateralValueInUSD(liquidator);

        MockV3Aggregator(wBTCUsdPriceFeed).updateAnswer(NEW_PRICE);

        uint256 liquidatorCollateralValueAfter = dscEngine
            .getAccountCollateralValueInUSD(liquidator);

        uint256 diffToDeposit = liquidatorCollateralValueBefore -
            liquidatorCollateralValueAfter;
        uint256 diffToDepositInwBTC = dscEngine.getTokenAmountFromUSDValue(
            wBTC,
            diffToDeposit
        );
        // Mint the difference plus the additional that will be used to mint
        // DSC to liquidate the account.
        uint256 additionalDSCCollateral = dscEngine.getTokenAmountFromUSDValue(
            wBTC,
            LIQUIDATION_COLLATERAL
        );
        uint256 totalToMint = diffToDepositInwBTC + additionalDSCCollateral + 2;

        // So that liquidator's collateral value is not impacted by this price drop
        // we mint and deposit wBTC to balance the collateral value.
        // Then, make liquidator have additional 100 DSC to liquidate the account.

        vm.startPrank(liquidator);
        ERC20Mock(wBTC).mint(liquidator, totalToMint);
        ERC20Mock(wBTC).approve(address(dscEngine), totalToMint);
        dscEngine.depositCollateral(wBTC, diffToDepositInwBTC + 2);
        dscEngine.depositCollateralAndMintDSC(
            wBTC,
            additionalDSCCollateral,
            LIQUIDATION_DSC
        );
        vm.stopPrank();

        _;
    }

    function test_RevertWhen_LiquidatingAnAccountThatHasHealthyHealthFactor()
        public
        twoProtocolUsers
    {
        // At the start, all users have a healthy health factor of 1.
        // Test user 2 attempts to liquidate user 1.
        vm.startPrank(TEST_USER_2);
        vm.expectPartialRevert(
            DSCEngine.DSCEngine__HealthFactorNotLiquidatable.selector
        );
        dscEngine.liquidateAccount(wETH, TEST_USER_1, 1000 ether);
        vm.stopPrank();
    }

    function test_LiquidatingUsersAwardsTheLiquidatorWithCollateralTokensPlusBonusIfApplicable()
        public
        twoProtocolUsers
        liquidatable(TEST_USER_1)
    {
        uint256 wBTCBalBefore = ERC20Mock(wBTC).balanceOf(TEST_USER_2);

        // A tenth of the outward collateral amount is awarded to the liquidator
        // in addition to the collateral tokens of the liquidated account that are
        // worth the DSC debt covered.
        // The liquidator does not always receive this bonus but at the minimum they receive
        // collateral worth the DSC debt they're covering.
        uint256 expectedMinOutput = dscEngine.getTokenAmountFromUSDValue(
            wBTC,
            LIQUIDATION_DSC
        );
        uint256 maxBonus = (expectedMinOutput * LIQUIDATION_BONUS) /
            LIQUIDATION_PRECISION;
        uint256 expectedMaxOutput = expectedMinOutput +
            maxBonus +
            wBTCBalBefore;

        vm.startPrank(TEST_USER_2);
        dsc.approve(address(dscEngine), LIQUIDATION_DSC);
        dscEngine.liquidateAccount(wBTC, TEST_USER_1, LIQUIDATION_DSC);
        vm.stopPrank();

        uint256 wBTCBalAfter = ERC20Mock(wBTC).balanceOf(TEST_USER_2);

        // wBTC balance of the liquidator should be greater than before the liquidation.
        assertGt(wBTCBalAfter, wBTCBalBefore);

        // The liquidator should receive at least the DSC debt worth of collateral.
        assertGe(wBTCBalAfter - wBTCBalBefore, expectedMinOutput);
        assertLe(wBTCBalAfter - wBTCBalBefore, expectedMaxOutput);
    }

    function test_RevertWhen_LiquidatingAnAccountThatHasInsufficientCollateralToRecoverDebt()
        public
        twoProtocolUsers
        liquidatable(TEST_USER_2)
    {
        // dip the price of wBTC to $10.
        uint256 liquidatorCollateralValueBefore = dscEngine
            .getAccountCollateralValueInUSD(TEST_USER_1);

        MockV3Aggregator(wBTCUsdPriceFeed).updateAnswer(10e8);

        uint256 liquidatorCollateralValueAfter = dscEngine
            .getAccountCollateralValueInUSD(TEST_USER_1);

        uint256 diffToDeposit = liquidatorCollateralValueBefore -
            liquidatorCollateralValueAfter;

        uint256 diffToDepositInwBTC = dscEngine.getTokenAmountFromUSDValue(
            wBTC,
            diffToDeposit
        );

        // Mint the difference plus the additional that will be used to mint
        // DSC to liquidate the account.
        uint256 additionalDSCCollateral = dscEngine.getTokenAmountFromUSDValue(
            wBTC,
            LIQUIDATION_COLLATERAL
        );

        uint256 totalToMint = diffToDepositInwBTC + additionalDSCCollateral;

        // Mint 2x collateral and DSC to liquidator to cover the debt.
        vm.startPrank(TEST_USER_1);
        ERC20Mock(wBTC).mint(TEST_USER_1, totalToMint);
        ERC20Mock(wBTC).approve(address(dscEngine), MAX_APPROVAL);
        dscEngine.depositCollateral(wBTC, totalToMint);
        dscEngine.mintDSC(LIQUIDATION_DSC);
        dsc.approve(address(dscEngine), LIQUIDATION_DSC);

        vm.expectRevert(DSCEngine.DSCEngine__AccountNotLiquidatable.selector);
        dscEngine.liquidateAccount(wBTC, TEST_USER_2, LIQUIDATION_DSC);
        vm.stopPrank();
    }
}
