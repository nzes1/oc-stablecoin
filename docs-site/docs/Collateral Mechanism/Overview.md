---
hide_title: true
pagination_next: 'Collateral Mechanism/Design' 
---

import DocCardList from '@theme/DocCardList';

# Overview

The oc-stablecoin protocol draws inspiration from MakerDAO, allowing users to supply collateral in both crypto assets and Real-World Assets (RWAs). Currently, the protocol exclusively _**supports crypto assets**_, with plans to integrate RWA support in the future.

As outlined in Chainlink's article on Stablecoins ([_Stablecoins, but actually_](https://blog.chain.link/stablecoins-but-actually/)), oc-stablecoin exhibits the following key feature regarding the collateral used to mint DSC:

#### _Exogenous Crypto Collateral_

Following Chainlink's definition, exogenous collateral in this context refers to assets entirely distinct from the protocol itself. To clarify, collateral is classified as exogenous if the following three questions yield the stated answers; otherwise, it is considered endogenous:

1. *If the stablecoin fails, does the underlying collateral also fail* - **No**
2.  *Was the collateral created solely for the purpose of being collateral?* - **No**
3.  *Does the protocol own the issuance of the underlying collateral?* - **No**

Based on these responses, the crypto collateral assets utilized by this protocol are considered **exogenous**.

:::tip Learn more about collateral in these sections:
:::
<DocCardList/>