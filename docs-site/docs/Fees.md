---
hide_title: true
sidebar_label: Protocol Fees
toc_min_heading_level: 2
toc_max_heading_level: 6
---

## Protocol Fees

The protocol implements two types of fees: a continuous protocol fee applied to open vaults and a one-time penalty levied during liquidation events.

## 1. Protocol Fee (1% APR)

The protocol fee, set at an annual percentage rate (APR) of 1%, can be viewed as the cost for users borrowing DSC against their collateral. This fee accrues continuously as long as a user's vault remains open and has an outstanding DSC debt.

**Use of Protocol Fees**

Similar to other decentralized finance (DeFi) protocols, the accrued protocol fees can serve various functions within the ecosystem. For instance, these fees could be:

* *Distributed to Governance Token Holders -* Rewarding those who participate in the protocol's governance.
* *Used for Buy-Back and Burn Mechanisms -* Reducing the supply of the governance token, potentially increasing its value.
* *Allocated to a Protocol Treasury -* Funding future development, audits, or other operational expenses.
* *Used to Offset Bad Debt -* In scenarios where liquidations are insufficient to cover outstanding debt, a portion of the collected fees might be used to mitigate the protocol's losses. MakerDAO, for example, utilizes stability fees (a form of protocol fee) in its Debt Auction system to recapitalize the protocol in case of undercollateralization.

### Calculation of Protocol Fee

The protocol fee is calculated based on the outstanding DSC debt, the annual percentage rate, and the duration the debt has been outstanding.

* *Debt (D):* The principal amount of DSC borrowed.
* *Annual Interest Rate (r)*: 1% or 0.01 (as a decimal).
* *Time (T):* The duration the debt has been outstanding, expressed in years.

The basic formula for simple interest is:

$$
Interest = Principal \times Rate \times Time
$$

In the context of the protocol fee, this translates to:

$$
Interest = debt \times rate \times time \quad (\text{where } time \text{ is in years})
$$

Since time in smart contracts is typically tracked in seconds, we need to convert the duration to years. There are approximately 31,536,000 seconds in a year or simply `365 days` when expressed in solidity time varibles .

Therefore, the time in years can be calculated as:

$$
Time\_In\_Years = \frac{Time\_In\_Seconds}{Seconds\_In\_A\_Year}
$$

Substituting this into the interest formula, we get the accrued protocol fee:

$$
Protocol\ Fee = debt \times rate \times \left( \frac{Time\_In\_Seconds}{Seconds\_In\_A\_Year} \right)
$$

This can be rearranged for computational efficiency to:

$$
Protocol\ Fee = \frac{debt \times rate \times Time\_In\_Seconds}{Seconds\_In\_A\_Year}
$$

### Fee Deduction

While the protocol fee is calculated in DSC, the fee is actually deducted from the collateral backing the vault. Therefore, when a fee is applied, the protocol determines the DSC amount owed and then calculates the equivalent value of that DSC in the underlying collateral asset at the current market price. This equivalent amount of collateral is then accounted for (or "charged") from the vault. (*The same design applies to liquidation penalty charge discussed below.*)

::::::info 
It's important to understand that the accrued protocol fee isn't necessarily deducted continuously in real-time. Instead, the protocol tracks the outstanding DSC debt and the **time elapsed since the last update to that debt**. The accumulated protocol fee is typically calculated and applied whenever an operation occurs that changes the DSC debt within a vault. 

At that point, the fee is calculated for the duration since the vault was opened or, more importantly, since the last time a fee calculation was performed and recorded for that vault. After applying the fee, the protocol updates the timestamp to the current time. This ensures that fees are charged accurately based on the actual time the debt was outstanding between modifications

:::tip In other words.
Protocol fees are charged based on the vault's outstanding DSC debt and the time elapsed since the last update to that debt. Fees are collected (calculated and accounted for) **whenever the vault's DSC debt changes** (*either increases or decreases*). The time elapsed since the last fee collection determines the amount of fee accumulated.
:::

::::::

::::danger Example
**Toggle the following section to see a practical example of fee application and deduction on user's vault.**

<details>
<summary> Protocol Fee Application & Deduction: A Practical Example </summary>

To illustrate how the 1% annual protocol fee is applied, let's consider a user's vault activity:

**Scenario:**

On January 1st, a user mints *100 DSC*.

**After 6 Months (July 1st) - Increasing Debt**

Six months later, the user adds more collateral and mints an additional *200 DSC*, bringing their total debt to **300 DSC**. At this point, the protocol calculates the fee accrued on the initial 100 DSC for those 6 months:

> Fee on 100 DSC for 6 months (0.5 years): `100 DSC * 0.01 * 0.5 = 0.5 DSC`

The equivalent value of **0.5 DSC in collateral is accounted for** from the user's vault. The protocol then notes the current time.

**End of Year (December 31st): Fee on the New Debt**

For the next 6 months, the vault holds 300 DSC. Suppose the user intends to close the vault at the end of the year. Let's see the fee accrued on this amount:

> Fee on 300 DSC since July till end of year December (0.5 years again):
> 
> `300 DSC * 0.01 * 0.5 = 1.5 DSC`

This **1.5 DSC worth of collateral will be accounted for** when the user will be closing their vault - i.e., burning all the DSC on that vault.

**Key Takeaway:**

Fees are calculated and accounted for *when the DSC debt changes*, based on the amount of debt outstanding and the time since the last fee calculation.

:::tip Important Note:

In this example, the total fee accrued by the end of the year is 2.0 DSC. If the fee were incorrectly calculated on 300 DSC for the entire year, it would be 3.0 DSC. This highlights that users are only charged for the actual amount of DSC they owe and the duration it has been outstanding.

:::

</details>
::::

## 2. Liquidation Penalty (1%)

The liquidation penalty is a one-time fee applied only when a vault becomes undercollateralized and is liquidated. This penalty is set at a flat rate of **1\%** of the total DSC debt of the liquidated vault, regardless of how long the vault was underwater or open.

### Calculation of Liquidation Penalty

The liquidation penalty is calculated as follows:

$$
Liquidation\ Penalty = debt \times Liquidation\_Penalty
$$

Where `Liquidation_Penalty` is the liquidation penalty rate (1% or 0.01).

This liquidation penalty amount, representing 1% of the liquidated debt, is typically deducted from the vault's locked collateral before any excess collateral is returned to the original vault owner. 

This penalty serves to disincentivize users from allowing their vaults to become undercollateralized and helps to compensate the protocol for the risk and effort involved in the liquidation process, especially once governance framework is in place.