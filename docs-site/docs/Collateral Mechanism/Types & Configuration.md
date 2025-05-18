---
hide_title: true
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

<Tabs queryString="types-configs">
  <TabItem value="types" label="Collateral Types" default>
    ## Collateral Types

    The protocol currently supports two types of collateral:

    1. **Native Ether:** As the protocol operates on the Ethereum blockchain.
    2. **ERC20 Compliant Tokens:** The protocol accepts both fully ERC20 compliant tokens and semi-compliant tokens. A notable example of a semi-compliant token is USDT. Governance must carefully consider the implications when adding support for ERC20-like tokens, taking into account the factors discussed in other sections.

  </TabItem>
  <TabItem value="configs" label="Collateral Configuration">
    ## Collateral Configuration

    Before a user can deposit any collateral, it must be configured within the protocol. This configuration can occur during deployment and after deployment. However, access control mechanisms, currently managed by an admin user through OpenZeppelin access control, restrict configuration to authorized addresses. In the current setup, the admin is the deployer address, but in a real-world scenario, this could be a multi-signature wallet when governance is integrated.

    Configuring collateral support involves setting various risk parameters and collateral parameters, as detailed below:

    1. *`collId`* - The unique identifier for the collateral type (e.g., the token symbol).

    2. *`tokenAddr`* - The address of the collateral ERC20 token. For native Ether, this is typically the zero address.
   
    3.  *`liqThreshold`* - The liquidation threshold ratio, scaled to $10^{18}$. This determines the maximum DSC that can be minted relative to the collateral's value. It represents the threshold at which a position is considered undercollateralized and subject to liquidation. In the protocol, this is expressed as a percentage. More details are provided below.

        > *The concept of "adjusted collateral" acknowledges that in a worst-case liquidation scenario, 100% of the collateral's current market value might not be recoverable. Instead, only a fraction of that value is "trusted" to cover the debt.*
        >
        > *Consider an example: If the liquidation threshold is 50 and liquidation precision is 100 (*take this simply as 2 decimals*), the protocol effectively considers only 50% of the raw collateral value as reliable backing for the debt.*
        >
        > The relationship can be expressed as:
        >
        > $$\text{Threshold percentage} = \frac{(\text{PRECISION} \times 100)}{\text{OVER-COLLATERALIZATION PERCENTAGE}}$$
        >
        > ***Note that the above expression is  generic and can be adopted for any precision, specifically the 18 decimals used in this protocol*.**
        >
        > ---
        > For example, suppose ETH collateral is given an Over-collateralization requirement of 170%, then the Liquidation Threshold Percentage can be computed as follows using a precision of 18 decimals:
        >
        > $$\text{Liquidation Threshold percentage} = \frac{(\text{$10^{18}$} \times 100)}{\text{170}}$$
        >
        > $$\text{Liquidation Threshold percentage} = 588235294117647058 (58.8\%) $$
        >
        > ---
    4.  *`priceFeed`* - The address of the Chainlink price feed for this collateral.
   
    5.  *`tknDecimals`* - The number of decimals for the collateral token, crucial for ensuring proper scaling in calculations, especially for ERC20 tokens.

### Post-Configuration

Once a collateral type is configured, users can deposit that collateral to back the minting of DSC.

> It's important to note that once collateral parameters are set, they are ***immutable***, meaning their values cannot be changed or modified, even by the admin. This ensures the security of the protocol's core elements.

However, an admin can completely remove a collateral configuration, but only if no outstanding open vaults are backed by that collateral. Removing a configuration deletes the collateral parameters, preventing any further operations on that collateral type (e.g., users cannot deposit new collateral of that type). The protocol includes a safeguard to prevent accidental locking of user funds by ensuring that configuration removal is only possible when no vaults are associated with that collateral.
  </TabItem>
 
</Tabs>