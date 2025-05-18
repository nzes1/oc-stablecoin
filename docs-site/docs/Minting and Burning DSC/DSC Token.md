---
hide_title: true
sidebar_label: The DSC Token
toc_min_heading_level: 2
toc_max_heading_level: 6
pagination_next: 'Minting and Burning DSC/Minting-Redeeming'

---

## DSC Token Standard and Inherited Functions
The DSC token implemented by this protocol is a fully compliant ERC20 token, inheriting its standard functionalities from [OpenZeppelin's ERC20 implementation](https://docs.openzeppelin.com/contracts/5.x/api/token/erc20#ERC20) . This means that all public and external functions defined in the OpenZeppelin ERC20 contract are available for users to manage their DSC tokens once minted.

## Access-Controlled Functions

The `burn(value)` and `burnFrom(account, value)` functions, which are part of the [ERC20Burnable extension](https://docs.openzeppelin.com/contracts/5.x/api/token/erc20#ERC20Burnable), are access-controlled within the DSC contract. 

In this protocol, only authorized users (*currently the DSCEngine contract*) can call these functions directly to manage the burning of DSC during the redemption process. Users interact with the `redeemCollateral()` and `burnDSC()` wrapper functions in the DSCEngine to initiate the burning of their DSC.

## Gasless Approvals via ERC20Permit

The DSC token also inherits the [ERC20Permit extension from OpenZeppelin](https://docs.openzeppelin.com/contracts/5.x/api/token/erc20#ERC20Permit). This standard, [EIP-2612](https://eips.ethereum.org/EIPS/eip-2612) allows for gasless token approvals through signed messages.

By leveraging the well-documented OpenZeppelin ERC20 and ERC20Permit standards, users and developers can refer to their official documentation for a comprehensive understanding of the available token management functions.

In summary, users can utilize the standard ERC20 functions (**excluding burn and burnFrom directly**) to manage their DSC and benefit from gasless approvals via ERC20Permit. The primary protocol-specific functions for interacting with the minting and redeeming mechanisms are the `mintDSC` and `burnDSC` functions within the DSCEngine contract.