// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Permit} from "@openzeppelin/contracts@5.1.0/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title DecentralizedStableCoin (DSC)
 * @author Nzesi
 * @notice ERC20-compliant decentralized stablecoin pegged to the US Dollar.
 * Minting is permissionless but collateralized: users must deposit exogenous
 * crypto assets to mint new DSC, ensuring algorithmic and decentralized stability.
 * @dev This contract implements the ERC20 standard using OpenZeppelin's library.
 * Minting and burning are restricted to the DSCEngine contract via Ownable access control.
 */
contract DecentralizedStableCoin is Ownable, ERC20Burnable, ERC20Permit {

    uint256 private constant MINIMUM_BURN_AMOUNT = 1;

    error DecentralizedStableCoin__InsufficientBurnAmount(uint256 minimumBurnAmount, uint256 burnAmount);
    error DecentralizedStableCoin__InsufficientBalanceToBurn(uint256 balance, uint256 burnAmount);
    error DecentralizedStableCoin__CannotMintZeroAmountOfTokens();
    error DecentralizedStableCoin__InvalidRecipientAddress();

    /**
     * @notice Initializes the DecentralizedStableCoin with name and symbol.
     * @dev Also sets the EIP-712 domain separator via ERC20Permit using the same name.
     */
    constructor() Ownable(msg.sender) ERC20("DecentralizedStableCoin", "DSC") ERC20Permit("DecentralizedStableCoin") {}

    /**
     * @notice Burns a specified amount of DSC tokens from the protocol's balance.
     * @dev Can only be called by the DSCEngine contract (owner). When users request
     * to burn tokens, their DSC is first transferred to the DSCEngine, which then
     * executes the burn to maintain control and enforce protocol logic.
     * @param burnTokensAmt The number of tokens to burn.
     */
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

    /**
     * @notice Mints new DSC tokens to a specified user address.
     * @dev Can only be called by the DSCEngine contract (owner). The recipient
     * address must be valid and the mint amount must be greater than zero.
     * Used to issue stablecoins when users deposit sufficient collateral.
     * @param account The address to receive the newly minted tokens.
     * @param mintAmt The amount of tokens to mint.
     */
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

    /**
     * @dev Overrides burnFrom to prevent direct user access, ensuring burn is only
     * callable by the DSCEngine (owner) for proper access control.
     */
    function burnFrom(address account, uint256 value) public override onlyOwner {
        super.burnFrom(account, value);
    }

}
