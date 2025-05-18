---
hide_title: true
sidebar_label: Liquidation Rewards Mechanism
toc_min_heading_level: 2
toc_max_heading_level: 6
---

import useBaseUrl from '@docusaurus/useBaseUrl';
import ThemedImage from '@theme/ThemedImage';

## Liquidation Rewards Mechanism

The protocol incentivizes the timely liquidation of undercollateralized vaults through a dual-reward system designed to protect protocol solvency and encourage efficient market participation. The liquidation reward is calculated based on two primary factors:

1.  **Time-Decaying Collateral Discount** encouraging rapid liquidation.
2.  **Risk-Adjusted Liquidator Reward -** Scaling rewards based on the size and risk of the liquidated debt.

### 1. Time-Decaying Collateral Discount

To incentivize liquidators to act swiftly when a vault becomes undercollateralized, the protocol offers a time-dependent discount on the collateral to be received by the liquidator. This discount starts at a maximum value and linearly decreases over a one-hour window.

**Goal:** Minimize protocol risk by promoting rapid liquidation of unhealthy vaults.

>It's crucial to understand that the discount is applied to the value of the collateral the liquidator receives in return for repaying the debt, not directly to the debt itself.

**Example**

Consider a vault with;

* *DSC Debt:* 100 DSC (pegged to $1)
* *Collateral Value:* Initially $150
* *Liquidation Trigger:* Collateral value drops to $140 (below the required overcollateralization ratio, e.g., 150%).

The liquidation process for this vault would be:

1.  A liquidator repays the full DSC debt: 100 DSC (worth $100).
2.  In return, the liquidator receives collateral from the vault with a value equal to the repaid debt plus a time-based discount. For example, with a 3% discount, they would receive collateral worth $100 + ($100 \* 0.03) = $103.
3.  **Liquidator Profit:** If the liquidator can sell this collateral for its market value of \$103, they make a profit of \$3.

#### Mechanics of the Time-Decaying Discount

* **Initial Discount:** The discount starts at a maximum of **3%** (this value is controllable by governance) immediately when a vault becomes undercollateralized/ marked to be underwater (time T+0).
* **Linear Decay:** The discount decreases linearly over the first **1 hour (60 minutes)**.
* **Minimum Discount:** After 1 hour, the discount reaches and remains at a minimum value of **1.8%**.

**Example of Discount Decay Over Time**

| Time After Undercollateralization | Discount Rate | Collateral Value Received by Liquidator (for 100 DSC debt) |
| :-------------------------------- | :------------ | :-------------------------------------------------------- |
| T+0 (Immediately)               | 3.0%        | $100 + ($100 \* 0.03) = $103                               |
| T+30 minutes                      | 2.4%        | $100 + ($100 \* 0.024) = $102.4                             |
| T+60 minutes                      | 1.8%        | $100 + ($100 \* 0.018) = $101.8                             |
| T > 60 minutes                    | 1.8%        | $100 + ($100 \* 0.018) = $101.8                             |

#### Risks Mitigated by This Design

1. **Protocol Insolvency Risk** 
   
   By incentivizing rapid liquidation, the protocol reduces the time window during which the value of the undercollateralized collateral can further decline, potentially leading to bad debt (*where the collateral value is less than the outstanding DSC*).

2. **Liquidator Inaction** 
   
   The decaying discount creates a competitive environment for liquidators. Early actors are rewarded with a higher discount, encouraging prompt action. Late liquidators receive a smaller benefit, reducing the incentive for prolonged inaction.
3. **Market Volatility Exposure** 
   
   Faster liquidations minimize the protocol's exposure to the price volatility of the collateral assets backing the DSC.

### 2. Risk-Adjusted Liquidator Rewards

In addition to the time-decaying discount, the protocol implements a risk-adjusted reward system to further incentivize liquidators, particularly for larger and potentially riskier debt positions. This system uses a **clamped linear (piecewise linear)** model to determine the reward based on the size of the debt being liquidated.

#### Formula

The risk-adjusted reward factor is governed by the following equation:

$$
\text{Risk-Adjusted Rewards} = \min(\max(k \times \text{Debt}, R_{\text{min}}), R_{\text{max}})
$$


Where:

* **`k` (Proportionality Constant):** Represents the percentage of the debt given as a reward.
    * **k = 0.5% (0.005)** for collateral with less than 150% overcollateralization.
    * **k = 1.5% (0.015)** for collateral with 150% or more overcollateralization.
        
        > *Rationale:* Riskier collateral (higher overcollateralization requirements) warrants a higher `k` to compensate liquidators for the increased volatility and potential difficulty in liquidating.

* **$R_{\text{min}}$ (Minimum Reward):** A floor value set at **10 DSC (equivalent to $10)**.
    
    > *Rationale:* Ensures that even liquidating small debt positions is economically viable for liquidators, covering gas costs and providing a base incentive. This is particularly important for the protocol's minimum allowed debt of 100 DSC, where the proportional reward alone for a 100 DSC vault would be very small (*0.5 DSC and 1.5 DSC for collaterals with \<150% OC and \>=150% respectively*).

* **$R_{\text{max}}$ (Maximum Reward):** A cap value set at **5000 DSC (equivalent to $5000)**.
    > *Rationale:* Prevents the liquidation reward from becoming excessively large for very high debt positions, which could potentially destabilize the reward system and the protocol's economics. This cap ensures a predictable and controlled reward range.

**Impact of Parameters**

* **Small Debt Positions:** For the smallest allowed debt (100 DSC), the calculated reward (`k × Debt`) would be 0.5 DSC or 1.5 DSC, both lower than `R_min`. Therefore, liquidators are always guaranteed a minimum reward of 10 DSC for any liquidation.
* **Large Debt Positions:** For very large debts (e.g., in the millions of DSC), the calculated reward would be substantial. However, the `R_max` cap ensures that the reward never exceeds 5000 DSC.

**Examples of $R_{\text{max}}$ Impact**

* With a 110% overcollateralization requirement (using k = 0.005), the reward reaches the 5000 DSC cap when the debt is around 1,000,000 DSC.
* With a 150% overcollateralization requirement (using k = 0.015), the reward reaches the 5000 DSC cap at a lower debt level of approximately 333,333 DSC due to the higher proportionality constant.

### Visualizing the Risk-Adjusted Liquidator Rewards

The following graphs illustrate how the liquidation reward is calculated based on the size of the DSC debt and the risk profile of the collateral. 

:::info Note
It's important to note that while the reward is calculated based on DSC value, the liquidator ultimately receives an equivalent value in the liquidated collateral asset.
:::

#### Graph 1: Lower Risk Collateral, k=0.5\% (*k = 0.005*)

*Graph showing the reward structure for collateral requiring lower overcollateralization (less than 150%).*

For lower risk collateral, the value of `k`, the proportionality constant, is 0.5\%

<ThemedImage
    alt="Docusaurus themed image"
    sources={{
        light: useBaseUrl('/img/liquidation-rewards-graph-low-risk-grey.png'),
        dark: useBaseUrl('/img/liquidation-rewards-graph-low-risk.png'),
    }}
/>

:::tip Key Observations

* **Minimum Reward ($R_{\text{min}}$) -** For lower risk collateral, the reward remains at the minimum of 10 DSC (*equivalent value in collateral*) for debt sizes up to approximately 2000 DSC (indicated by the 🔺). Beyond this point, the reward starts to increase linearly with the debt.
  
* **Linear Scaling -** The reward increases proportionally to the debt (at a rate of `k = 0.005`) for debt sizes between 2000 DSC and 2,000,000 DSC (*the point where `R_max` is reached*).
* **Maximum Reward ($R_{\text{max}}$) -** Once the debt reaches 2,000,000 DSC (*indicated conceptually around 2,000,000 DSC, and marked on the graph with* 🔶), the reward is capped at 5000 DSC (*equivalent value in collateral*). For any debt exceeding this level, the liquidator's reward will remain at this capped value.
:::

#### Graph 2: Higher Risk Collateral, k=1.5\% (*k = 0.015*)

*This graph shows the reward structure for collateral requiring higher overcollateralization (150% or more).*

For higher risk collateral, the value of `k`, the proportionality constant, is 1.5\%

<ThemedImage
    alt="Docusaurus themed image"
    sources={{
        light: useBaseUrl('/img/liquidation-rewards-graph-high-risk-grey.png'),
        dark: useBaseUrl('/img/liquidation-rewards-graph-high-risk.png'),
    }}
/>

:::tip Key Observations:

* **Minimum Reward ($R_{\text{m}}$):** For higher risk collateral, the reward remains at the minimum of 10 DSC (*equivalent value in collateral*) for debt sizes up to approximately 666.667 DSC (*indicated by the*  🔺, *shown around 600 DSC for illustrative purposes on the graph*). Beyond this point, the reward starts to increase linearly with the debt.
* **Linear Scaling:** The reward increases proportionally to the debt (at a rate of `k = 0.015`) for debt sizes between approximately 666.667 DSC and approximately 333,333 DSC (*the theoretical point where `R_max` is reached*).
* **Maximum Reward ($R_{\text{max}}$):** Once the debt reaches approximately 333,333 DSC (*illustrated around 350,000 DSC and marked on the graph* with 🔶), the reward is capped at 5000 DSC (*equivalent value in collateral*). For any debt exceeding this level, the liquidator's reward will remain at this capped value.
:::

---


**Important Note on Value Scaling**

All values involved in the liquidation process, including collateral values, DSC debt, and discounts, are scaled by `1e18` within the smart contracts to maintain precision and avoid truncation due to the EVM capabilities around fractions. For example, a value of $140 would be represented as `140e18`, and a percentage like 10% would be `0.1e18`.


## Conclusion

The combination of the time-decaying collateral discount and the risk-adjusted liquidator reward creates a robust and dynamic system designed to ensure the efficient and timely liquidation of undercollateralized vaults, safeguarding the protocol's solvency. The specifics of how these rewards are applied during the `liquidateVault` function are detailed in the [Link to Liquidation Function Documentation].