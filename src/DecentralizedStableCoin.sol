// SPDX-License-Identifier: MIT

/*//////////////////////////////////////////////////////////////
                            CONTRACT LAYOUT
//////////////////////////////////////////////////////////////*/

/**
 * @dev Contract Layout based on RareSkills Solidity Style guide
 * here: https://www.rareskills.io/post/solidity-style-guide which expounds on
 * Solidity's recommended guide on the docs.
 * Type Declarations
 * State Variables
 * Events
 * Errors
 * Modifiers
 * Constructor
 * Functions:
 *  External
 *      External View
 *      External pure
 *  Public
 *      Public View
 *      Public pure
 *  Internal
 *      Internal View
 *      Internal Pure
 *  Private
 *      Private View
 *      Private Pure
 *
 */
pragma solidity 0.8.24;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author @nzesi_eth
 * @notice The DecentralizedStableCoin contract is a decentralized stablecoin
 * that has its relative stability anchored or pegged to the US Dollar.
 * The coin uses exogenous collateral in form of crypto where for new coins
 * to be minted, the user must deposit collateral in the form of those crypto
 * assets. This makes the coin's minting mechanism decentralized and algorithmic.
 * The logic of the coin is defined in the DSCEngine contract. This contract
 * is the ERC20 implementation of the stablecoin.
 * @dev The ERC20 implementation uses the OpenZeppelin library for the
 * implementation of the ERC20 standard.
 * @dev Openzeppelin's Ownable Access Control utility is used to restrict minting
 * and burning to the owner of the contract - which is the DSCEngine contract.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 private constant MINIMUM_BURN_AMOUNT = 1;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DecentralizedStableCoin__InsufficientBurnAmount(
        uint256 minimumBurnAmount,
        uint256 burnAmount
    );

    error DecentralizedStableCoin__InsufficientBalanceToBurn(
        uint256 balance,
        uint256 burnAmount
    );

    error DecentralizedStableCoin__CannotMintZeroAmountOfTokens();

    error DecentralizedStableCoin__InvalidRecipientAddress();

    /**
     * @notice The constructor initializes the ERC20 token with the name
     * `DecentralizedStableCoin` and the token symbol `DSC`.
     */
    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The burn function allows users to burn their tokens.
     * @dev User has to burn at least 1 token and cannot burn more than they have.
     * @dev Only the owner can burn tokens - the owner is the DSCEngine contract.
     * @param burnTokensAmt The amount of tokens to burn.
     */
    function burn(uint256 burnTokensAmt) public override onlyOwner {
        /// @dev Get the balance of `msg.sender`
        uint256 userBalance = balanceOf(msg.sender);

        /// User has to burn at least 1 token
        if (burnTokensAmt <= 0) {
            revert DecentralizedStableCoin__InsufficientBurnAmount(
                MINIMUM_BURN_AMOUNT,
                burnTokensAmt
            );
        }

        /// User cannot burn more than they have
        if (burnTokensAmt > userBalance) {
            revert DecentralizedStableCoin__InsufficientBalanceToBurn(
                userBalance,
                burnTokensAmt
            );
        }

        /// If the user has enough tokens, burn the tokens
        super.burn(burnTokensAmt);
    }

    /**
     * @notice The mint function allows the owner(DSCEngine) to mint new tokens.
     * @dev The recipient of the minted tokens has to be a valid address
     * and the amount has to be greater than 0.
     * @param account The recipient of the minted tokens.
     * @param mintAmt The amount of tokens to mint.
     */
    function mint(
        address account,
        uint256 mintAmt
    ) public onlyOwner returns (bool success) {
        /// Recipient of the minted tokens has to be a valid address
        if (account == address(0)) {
            revert DecentralizedStableCoin__InvalidRecipientAddress();
        }
        /// Amount has to be greater than 0
        if (mintAmt <= 0) {
            revert DecentralizedStableCoin__CannotMintZeroAmountOfTokens();
        }

        /// Mint the tokens
        _mint(account, mintAmt);
        return true;
    }
}
