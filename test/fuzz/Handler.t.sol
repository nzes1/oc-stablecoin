// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts@5.1.0/mocks/token/ERC20Mock.sol";
import {SimulatedUsers, ActorsLibrary} from "./ActorsLibrary.sol";

contract Handler is Test {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    using ActorsLibrary for SimulatedUsers;

    SimulatedUsers internal actors;
    address internal currentActor;

    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    ERC20Mock wETH;
    ERC20Mock wBTC;
    uint96 private constant MAX_DEPOSIT_AMOUNT = type(uint96).max;
    uint8 private constant MAX_DSC_FACTOR = 2;

    // Ghost variables
    uint256 private ghost_zeroAddressActorCount;
    uint256 private ghost_successfulRedeemCollateral;
    uint256 private ghost_zeroCollateralForSelectedToken;

    // Count the number of calls to each function
    mapping(string funcName => uint256 count) internal numOfCalls;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Save an actor - an actor is a fuzzed msg.sender that the fuzzer
     * generates for a function call. The actor is saved in the actors list
     * if not already saved and the currentActor is set to the msg.sender.
     */
    modifier createActor() {
        actors.saveSender(msg.sender);
        currentActor = msg.sender;
        _;
    }

    /**
     * @dev Use a saved actor especially for calls that require a previously
     * active user of the protocol such as redeeming collateral needs a user to
     * have deposited collateral before and have a balance.
     */
    modifier useActor(uint256 senderSeed) {
        address pickedActor = actors.selectRandomSender(senderSeed);
        currentActor = pickedActor;
        _;
    }

    /**
     * @dev Count the number of calls to a function
     */
    modifier countCall(string memory funcName) {
        numOfCalls[funcName]++;
        _;
    }

    constructor(DecentralizedStableCoin _dsc, DSCEngine _dscEngine) {
        dsc = _dsc;
        dscEngine = _dscEngine;

        // Hardcoded
        address[] memory tokens = dscEngine.getCollateralTokens();
        wETH = ERC20Mock(tokens[0]);
        wBTC = ERC20Mock(tokens[1]);
    }

    /**
     * @dev Deposit collateral into the DSC Engine
     * @param tokenSeed - A random seed to select a collateral token
     * @param amount - The amount of collateral to deposit
     */
    function depositCollateral(uint256 tokenSeed, uint256 amount) public createActor countCall("depositCollateral") {
        ERC20Mock tokenAddr = _getCollateralTokenFromSeed(tokenSeed);

        // Avoid depositing zero collateral amount
        amount = bound(amount, 1, MAX_DEPOSIT_AMOUNT);

        // The tokens to be deposited needs to be minted
        // and the DSC Engine needs to be approved to spend them.
        vm.startPrank(currentActor);
        tokenAddr.mint(currentActor, amount);
        tokenAddr.approve(address(dscEngine), amount);

        dscEngine.depositCollateral(address(tokenAddr), amount);

        vm.stopPrank();
    }

    // function depositAndMintDSC(
    //     uint256 tokenSeed,
    //     uint256 collateralAmount,
    //     uint256 dscAmount
    // ) public createActor countCall("depositAndMintDSC") {
    //     ERC20Mock tokenAddr = _getCollateralTokenFromSeed(tokenSeed);

    //     collateralAmount = bound(collateralAmount, 1, MAX_DEPOSIT_AMOUNT);

    //     // The collateral total value.
    //     uint256 collateralTV = dscEngine.getValueInUSD(
    //         address(tokenAddr),
    //         collateralAmount
    //     );

    //     vm.startPrank(currentActor);
    //     ERC20Mock(tokenAddr).mint(currentActor, collateralAmount);
    //     ERC20Mock(tokenAddr).approve(address(dscEngine), collateralAmount);

    //     dscAmount = bound(dscAmount, 1, collateralTV / MAX_DSC_FACTOR);
    //     dscEngine.depositCollateralAndMintDSC(
    //         address(tokenAddr),
    //         collateralAmount,
    //         dscAmount
    //     );
    //     vm.stopPrank();
    // }

    /**
     * @dev Redeem collateral from the DSC Engine
     * @param tokenSeed - A random seed to select a collateral token
     * @param amount - The amount of collateral to redeem
     * @param senderSeed - A random seed to select an actor from the list of actors
     * that have already interacted with the protocol.
     */
    function redeemCollateral(uint256 tokenSeed, uint256 amount, uint256 senderSeed)
        public
        useActor(senderSeed)
        countCall("redeemCollateral")
    {
        // If the actor is the zero address, then there is no need to redeem collateral
        // because this implies no actor has deposited collateral.

        if (currentActor == address(0)) {
            ghost_zeroAddressActorCount++;
            return;
        }
        // Valid token to withdraw
        ERC20Mock tokenAddr = _getCollateralTokenFromSeed(tokenSeed);

        uint256 maxRedeemableCollateral = dscEngine.getAccountCollateral(address(tokenAddr), currentActor);

        // A user might have collateral balance of one token and not the other
        if (maxRedeemableCollateral == 0) {
            ghost_zeroCollateralForSelectedToken++;
            return;
        }
        amount = bound(amount, 1, maxRedeemableCollateral);

        vm.startPrank(currentActor);
        dscEngine.redeemCollateral(address(tokenAddr), amount);
        vm.stopPrank();

        ghost_successfulRedeemCollateral++;
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _getCollateralTokenFromSeed(uint256 tokenSeed) private view returns (ERC20Mock) {
        // Randomly select one of the two collateral tokens
        // Since they are only 2 collateral tokens, we can use a simple modulo operation
        // using the ternary operator.
        // If tokenSeed is even, return wETH, else return wBTC
        return (tokenSeed % 2 == 0) ? wETH : wBTC;
    }

    function callSummary() external view {
        console.log("Number of calls per function");
        console.log("*****************************");
        console.log("Deposit Collatteral: ", numOfCalls["depositCollateral"]);
        console.log("Redeem Collatteral: ", numOfCalls["redeemCollateral"]);
        // console.log("Deposit and Mint DSC: ", numOfCalls["depositAndMintDSC"]);

        console.log("Zero address actors: ", ghost_zeroAddressActorCount);
        console.log("Successful redeems: ", ghost_successfulRedeemCollateral);
        console.log("Zero collateral: ", ghost_zeroCollateralForSelectedToken);
    }
}
