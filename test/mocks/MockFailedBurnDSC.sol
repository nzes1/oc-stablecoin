// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Permit} from "@openzeppelin/contracts@5.1.0/token/ERC20/extensions/ERC20Permit.sol";

contract MockFailedBurnDSC is Ownable, ERC20Burnable, ERC20Permit {

    uint256 private constant MINIMUM_BURN_AMOUNT = 1;

    error DecentralizedStableCoin__InsufficientBurnAmount(uint256 minimumBurnAmount, uint256 burnAmount);

    error DecentralizedStableCoin__InsufficientBalanceToBurn(uint256 balance, uint256 burnAmount);

    error DecentralizedStableCoin__CannotMintZeroAmountOfTokens();

    error DecentralizedStableCoin__InvalidRecipientAddress();

    constructor() Ownable(msg.sender) ERC20("MockFailedBurnDSC", "DSC") ERC20Permit("DecentralizedStableCoin") {}

    function burn(uint256 burnTokensAmt) public override onlyOwner {
        uint256 userBalance = balanceOf(msg.sender);

        if (burnTokensAmt <= 0) {
            revert DecentralizedStableCoin__InsufficientBurnAmount(MINIMUM_BURN_AMOUNT, burnTokensAmt);
        }

        if (burnTokensAmt > userBalance) {
            revert DecentralizedStableCoin__InsufficientBalanceToBurn(userBalance, burnTokensAmt);
        }

        super.burn(burnTokensAmt);
    }

    // mock of unsuccessful minting i.e., returning false on call.
    function mint(address account, uint256 mintAmt) public onlyOwner returns (bool success) {
        if (account == address(0)) {
            revert DecentralizedStableCoin__InvalidRecipientAddress();
        }

        if (mintAmt <= 0) {
            revert DecentralizedStableCoin__CannotMintZeroAmountOfTokens();
        }

        _mint(account, mintAmt);
        return true;
    }

    function transferFrom(
        address, /*sender*/
        address, /*recipient*/
        uint256 /*amount*/
    )
        public
        pure
        override
        returns (bool)
    {
        return false;
    }

    // Prevent users from bypassing the access control of burn() and use the burnFrom()
    // of the ERC20Burnable to burn tokens
    function burnFrom(address account, uint256 value) public override onlyOwner {
        super.burnFrom(account, value);
    }

    // A recommencation from stackOverflow and foundry Github Issues to prevent coverage report from
    // including a contract like mocks.
    function test() public {}

}
