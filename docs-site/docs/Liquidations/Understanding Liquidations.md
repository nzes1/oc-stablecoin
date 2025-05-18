---
hide_title: true
sidebar_label: Understanding Liquidations
toc_min_heading_level: 2
toc_max_heading_level: 6
---

## Understanding Liquidations

Liquidation is a crucial mechanism within the protocol designed to protect it from accumulating bad debt. The protocol assesses the health of each over-collateralized vault by calculating a **health factor** ratio. This ratio compares the adjusted value of the collateral locked in a vault (adjusted based on the liquidation threshold, as detailed in the [Config & Risk Parameters](../Collateral%20Mechanism/Config%20&%20Risk%20Parameters?collateral-parameters=RiskParams#liquidation-threshold)) against the amount of DSC minted against that collateral.

**Health Factor: Maintaining Protocol Health**

For a vault to be considered healthy and not pose a risk of liquidation, its health factor must remain above 1 (*or simply `1e18` for precision purposes with 18 decimals*).

**Full Liquidations (Current Implementation)**

Currently, the protocol only supports full liquidations. To liquidate an undercollateralized vault and receive rewards, a liquidator must repay the entire outstanding DSC amount for that vault in a single transaction. 

:::info
Partial liquidations may be introduced in future protocol upgrades.
:::

**Identifying Unhealthy Vaults**

A vault is deemed **underwater** and eligible for liquidation when its health factor drops below 1 (`1e18`).

**Who Can Liquidate?**

Anyone can act as a liquidator to liquidate an underwater vault. The only restriction is that the owner of the vault cannot liquidate their own vault using the same vault address. However, they could potentially use a different address  (**effectively acting as a separate entity from the protocol's perspective**).

## The Liquidation Process and Rewards

When an underwater vault is liquidated, the liquidator supplies the full DSC debt of the vault and, in return, receives collateral from the liquidated vault as a reward. This reward mechanism is designed with two key components, both deducted from the vault's collateral:

1.  **Base Collateral Repayment -** The liquidator receives an amount of the vault's collateral equivalent in value to the DSC they repaid; *of course the amount is the full DSC debt for that vault*.
2.  **Liquidation Reward -** An additional amount of collateral is awarded to the liquidator, calculated based on two factors:
    * **Early Liquidation Bonus (Within 1 Hour) -** A larger reward is given to liquidators who liquidate a vault within the first hour after it becomes underwater. This incentivizes swift action to minimize protocol risk. The rationale behind this design is discussed at [Liquidation Rewards Mechanism](./Rewards%20Mechanism.md) section.
    * **Collateral Risk Premium -** A mandatory reward component, the size of which can be adjusted based on the perceived risk associated with the specific type of collateral backing the vault.

### Possible Outcomes of Liquidation

The liquidation process can have three distinct outcomes, depending on the amount of collateral available in the underwater vault

1.  **Sufficient Collateral for Full Liquidation**
    * The vault contains enough collateral to cover both the DSC-equivalent repayment to the liquidator and the full calculated liquidation rewards.
    * The liquidator receives both the DSC-equivalent collateral and the complete rewards.

2.  **Partial Rewards**
    * The vault has enough collateral to cover the DSC-equivalent repayment **but not the entirety of the liquidation rewards**.
    * The liquidator receives the DSC-equivalent collateral and as much of the calculated rewards as the remaining collateral allows. 
    
        :::danger warning
        In some cases, if the remaining collateral only covers the base repayment, the liquidator may receive zero additional reward.
        :::
        

3.  **Insufficient Collateral (Bad Debt Scenario)**
    * The vault does not hold enough collateral even to cover the DSC-equivalent repayment.
    * In this scenario, the liquidator does not receive any collateral from the liquidated vault.
    * Instead, the DSC they supplied for the repayment is refunded to them from the protocol. The protocol absorbs the resulting bad debt and takes ownership of the undercollateralized vault. Future governance mechanisms will define how the protocol manages and resolves these absorbed bad debt positions.

## Liquidation Flow (Conceptual)

The liquidation flow follows the following steps:

<details>

<summary> Liquidation Flow (Conceptual) - *Toggle here for the flow details* </summary>
1.  **Monitor Health Factors:** The protocol keepers(liqudators) continuously monitors the health factor of all vaults.
2.  **Identify Underwater Vault:** When a vault's health factor drops below the critical threshold (1 or `1e18`), it becomes eligible for liquidation. A liquidator can either mark it as underwater or directly initiate liquidation which will also mark the vault as underwater in a single call. The reason for separation of flagging and liquidating underwater vaults is covered in greater details in the [Liquidation Interface Functions](Liquidation%20Interface%20Functions.md).
3.  **Liquidator Initiates Liquidation:** Anyone can call the `liquidateVault` function, providing the address of the underwater vault and the amount of DSC equal to its outstanding debt.
4.  **Protocol Checks:** The protocol verifies the vault's unhealthy status and the DSC repayment amount.
5.  **Fee Deduction:** Protocol fees associated with the liquidation process are deducted from the locked collateral of the liquidated vault - both protocol fees and a liquidation penalty.
6.  **Reward Calculation:** The protocol calculates the liquidation rewards based on the early liquidation bonus and the collateral risk premium.
7.  **Collateral Seizure and Transfer:** Collateral from the liquidated vault is transferred to the liquidator (or credited to their internal balance).
8.  **DSC Burning:** The DSC supplied by the liquidator is burned, reducing the total supply.
9.  **Handling Insufficient Collateral:** If the collateral is insufficient, the liquidator is refunded with newly minted DSC, and the protocol takes ownership of the vault.
10. **Return of Excess Collateral:** Any remaining collateral after the liquidator is compensated and fees are paid is returned to the original vault owner.

</details>

The specifics of the reward calculation are detailed in the [Liquidation Rewards Mechanism](Rewards%20Mechanism.md) section.
