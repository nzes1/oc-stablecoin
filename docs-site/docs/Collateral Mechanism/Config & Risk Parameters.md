---
hide_title: true
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

<Tabs queryString="collateral-parameters">
  <TabItem value="Overview" label="Parameters Overview" default>
    The parameters listed at  [Collateral Configuration](./Types%20&%20Configuration?types-configs=configs) are defined through a careful assessment of the risks associated with each collateral added to the protocol.

    Some of these parameters are risk parameters, while others are configuration values based on the specific collateral crypto asset.

    These parameters can be broadly categorized into two:
        1. [Config Values Parameters](Config%20&%20Risk%20Parameters?collateral-parameters=ConfigValueParams)
        2. [Risk Parameters](./Config%20&%20Risk%20Parameters?collateral-parameters=RiskParams)
  </TabItem>
  
  <TabItem value="ConfigValueParams" label="Config Value Parameters">
    ## Config Values Parameters

    1. *`CollId`* - Typically the crypto token's symbol. 
        
        For fully ERC20 compliant tokens, this value can be obtained by calling the `symbol()` function of the token contract. The value is then stored as a `bytes32` value within the protocol. For Ether collateral, the string "ETH" can be directly passed, and this applies to any other supported collateral.

    2. *`tokenAddr`* - Simply the token's contract address. 
        
        In the protocol's getter functions, especially for collateral configurations, note how `ether` collateral is set to the zero address.

    3. *`tknDecimals`* - The number of decimal places the token supports. 

        Most ERC20 tokens use 18 decimals for precision. It is crucial to configure this value accurately to aid in the internal calculations of the protocol, particularly when determining the health factor and the permissible amount of DSC to be minted. 
        
        Decimals are also necessary for correctly calculating liquidation rewards. A separate variable for token decimals is needed because different components of the protocol use varying decimal precisions. For instance, Chainlink price feeds often use 8 decimals, while the DSC token itself uses 18 decimals.
  </TabItem>
  <TabItem value="RiskParams" label="Risk Parameters">
    ## Risk Parameters

    ## Summary
    The primary risk parameter within this protocol is the liquidation threshold. This threshold serves as a comprehensive control, encompassing several other risk considerations, some of which are established as fixed protocol constants, while others are determined dynamically by the protocol. This section will detail the liquidation threshold parameter, a core risk element, explaining its derivation and its application within the protocol.

    ## Liquidation Threshold
    
    This is a critical risk parameter that, alongside other constants within the protocol, plays a central role in maintaining the protocol's safety. The liquidation threshold is set as a percentage and is used to determine if a vault backed by a specific collateral is undercollateralized. 
    
    It's important to note that this value is specific to each collateral type and is determined by carefully evaluating the risks associated with that particular token.

    
    In the DeFi space, for example, on MakerDAO, the liquidation threshold for ETH collateral is set at 200% (*meaning \$200 worth of collateral for every \$100 of DAI stablecoins*).

        > This protocol employs a similar concept with a slight adjustment. (*Of course, once governance is implemented, it can establish potentially better and more realistic values.*)

    This protocol uses the name `liqThreshold` to mean Liquidation Threshold.

    ### Derivation of Liquidation Threshold

    To arrive at the liquidation ratio, we first consider the over-collateralization (OC) ratio. In most DeFi platforms, the OC is typically expressed as a percentage.

    In this oc-stablecoin protocol, the OC is chosen based on the stability or volatility of the collateral in question, but always above 100%. This ensures that the collateral's value always exceeds the value of the DSC minted against it.

    #### Over-collateralization (OC) Based On Volatility

    For collaterals with high volatility, the OC is set to values above 150%, inspired by MakerDAO's approach. For instance, ETH has an OC of 170%, and LINK has an OC of 160%. Remember that these values are set during deployment and can be changed when a governance team establishes the parameters. 
    
    > Again, these values are not set directly but indirectly via the `liqThreshold`, as you will see shortly.

    For relatively stable collaterals, such as stablecoins (*yes, the protocol allows users to deposit stablecoins to mint DSC stablecoins!* 😄), the OC is set below 150% but above 100%. An example is DAI with an OC of 110% and USDT with 120%. USDT has a higher OC than DAI due to its centralization governance concerns.

    > But wait ... *You might be asking yourself,* **why separation of OCs above and below 150%?🤷🏽**

    > It's crucial to note the reasoning behind the above OCs: the separation of OCs above and below 150% is significant later in liquidations. Collaterals with an OC above 150% are considered **HIGH risk** in this protocol, while those with an OC below 150% are considered **LOW risk**. 
    More details on this can be found in the Liquidations section of these docs.

    Once the OC is determined, the `liqThreshold` is calculated. This is the variable directly stored in the protocol, not the OC, although the OC can be easily derived from the `liqThreshold`.

    Before we formulate the `liqThreshold` calculation, let's understand its purpose with an analogy:

    #### Analogy

        Imagine you've pledged your house as collateral for a loan. In normal times, it might be worth \$300,000. However, if you need to sell it quickly (e.g., during a market downturn), you might only get 80% of its market value - around \$240,000.

        At this point, we can clearly point out these two:

        * *Total Market Value -* \$300,000
        * *"Trusted" Value in a Panic Sale -* \$240,000

        When the lender assesses your risk, they won't consider the full \$300,000; they'll focus on the \$240,000 because that's what they could realistically recover if they had to liquidate.

    ***DeFi Translation***

    Similarly, many stablecoin systems (*as is also with many lending & borrowing DeFi protocols*) don't use the entire collateral value; they apply a "liquidation threshold" (or safety buffer). 
    
    > In most DeFi protocols, this is achieved by multiplying by something like `Liquidation_Threshold / Liquidation_Precision`. For example, if `Liquidation_Threshold` is 50 (with `Liquidation_Precision` 100), the protocol effectively "trusts" only 50% of the collateral's value.

    In this protocol, the `liqThreshold` percentage is calculated using the formula:

    $$\text{liqThreshold percentage} = \frac{(\text{Precision Used} \times 100)}{\text{over-collateralization Percentage}}$$

    In the equation above, 100 represents 100%. The resulting `liqThreshold` percentage value will have the same number of decimals as the precision used. In the protocol, this precision is set to 18 decimals, so the `liqThreshold` will always be in 18 decimals.

    The value $\frac{100}{\text{over-collateralizationPercentage}}$ in the formula represents the trusted fraction of the collateral.

    **Examples (using 18 decimals for precision):**
    | Collateralization Percentage | Trusted Fraction               | liqThreshold                    |
| :--------------------------- | :-----------------------------     | :------------------------------ |
| 200%                         | $\frac{100}{200}$ = 0.5 (50%)      | $\frac{(10^{18} \times 100)}{200}$ = 500,000,000,000,000,000  |
| 170%                         | $\frac{100}{170}$ ≈ 0.5882 (58.82%)| $\frac{(10^{18} \times 100)}{170}$ ≈ 588,235,294,117,647,058 |
| 160%                         | $\frac{100}{160}$ = 0.625 (62.5%)  | $\frac{(10^{18} \times 100)}{160}$ = 625,000,000,000,000,000 |
| 120%                         | $\frac{100}{120}$ ≈ 0.8333 (83.33%)| $\frac{(10^{18} \times 100)}{120}$ ≈ 833,333,333,333,333,333 |
| 110%                         | $\frac{100}{110}$ ≈ 0.9090 (90.90%)| $\frac{(10^{18} \times 100)}{110}$ ≈ 909,090,909,090,909,090 |
  </TabItem>
</Tabs>