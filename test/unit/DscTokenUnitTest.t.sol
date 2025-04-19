// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Ownable} from "@openzeppelin/contracts@5.1.0/access/Ownable.sol";

contract DscTokenUnitTest is Test {

    DecentralizedStableCoin dscToken;
    address TEST_USER_1 = makeAddr("Test User 1");
    address TEST_USER_2 = makeAddr("Test User 2");
    address owner = makeAddr("DSC owner");

    function setUp() public {
        dscToken = new DecentralizedStableCoin();
        dscToken.transferOwnership(owner);
    }

    function _mint(address user, uint256 amount) internal {
        vm.startPrank(owner);
        dscToken.mint(user, amount);
        vm.stopPrank();
    }

    function test_RevertWhenNonOwnerAttemptsMintTokens() public {
        uint256 mintAmt = 1_000e18;
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);

        vm.startPrank(TEST_USER_1);
        dscToken.mint(TEST_USER_2, mintAmt);
        vm.stopPrank();
    }

    function test_RevertWhenMintingToZeroAddress() public {
        uint256 mintAmt = 1_000e18;

        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__InvalidRecipientAddress.selector);

        _mint(address(0), mintAmt);
    }

    function test_RevertWhenMintingZeroTokenAmount() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__CannotMintZeroAmountOfTokens.selector);

        _mint(TEST_USER_2, 0);
    }

    function test_MintingTokensIncreasesUsersBalance() public {
        uint256 mintAmt = 1_000e18;

        _mint(TEST_USER_2, mintAmt);

        assertEq(dscToken.balanceOf(TEST_USER_2), mintAmt);
    }

    function test_RevertWhenBurningZeroTokenAmount() public {
        uint256 minBurnAmt = 1;
        uint256 mintAmt = 1_000e18;

        _mint(TEST_USER_1, mintAmt);
        vm.expectRevert(
            abi.encodeWithSelector(
                DecentralizedStableCoin.DecentralizedStableCoin__InsufficientBurnAmount.selector, minBurnAmt, 0
            )
        );

        // The owner of dsc always burns the tokens
        vm.startPrank(owner);
        dscToken.burn(0);
        vm.stopPrank();
    }

    function test_RevertWhenOwnerBurnsMoreThanTheBalanceAvailable() public {
        uint256 mintAmt = 1_000e18;

        _mint(TEST_USER_2, mintAmt);

        // Transfer from TEST_USER_2 to owner to simulate burning
        vm.startPrank(TEST_USER_2);
        dscToken.transfer(owner, 500e18);
        vm.stopPrank();

        // Only 500 dsc has been transferred to owner to burn. Attempting to burn 700 dsc reverts
        vm.expectRevert(
            abi.encodeWithSelector(
                DecentralizedStableCoin.DecentralizedStableCoin__InsufficientBalanceToBurn.selector, 500e18, 700e18
            )
        );

        vm.startPrank(owner);
        dscToken.burn(700e18);
        vm.stopPrank();
    }

    function test_RevertWhenNonOwnerAttemptsToBurnTokensFromAnotherUser() public {
        address burnFrom = makeAddr("User to burn from");
        // Mint this user some tokens
        _mint(burnFrom, 100e18);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, TEST_USER_1));

        vm.startPrank(TEST_USER_1);
        dscToken.burnFrom(burnFrom, 50e18);
        vm.stopPrank();
    }

}
