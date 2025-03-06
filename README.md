
#### Key features for the permit functionality
- protected against cross-chain replay attacks: chain id is verified
- protected against contract collisions - sigs meant for contract A do not work on contract B if they share the same name/version due to separation by chainid
- Ensures replay resistance - refer to cyfrin's blog on eip712 too

- The Oz EIP712 contract/library/package automatically ensure that the signatures are replay resistant to cros-chain replays by ensuring that the chainid during signature/message hash generation is always equal to what was defined during deployment of the protocol. If that changed, then the msg hash is not formed. This is on lines 80 to 86 but specifically line 81 of the _domainSeparatorv4() in the EIP712.sol file. That's what I wanted to implement but Ozx has already. Will test it's working by writing a test for the same.====this is wrong
- Changed/revised my understanding for replay protection - as long as the chainid forms part of the final hash that gets signed, supplying a hash that has a different chainid automatically means a different hash thus sig and hash won't match - this is the protection now.
- i.e., If the chainId changes (e.g., moving from Ethereum to Polygon), the DOMAIN_SEPARATOR changes → the digest changes → the signature becomes invalid.

#### Why No Explicit chainId Check Is Needed
- Implicit Protection: When a user signs a permit, the signature is mathematically bound to the chainId used in the domain separator. If someone tries to replay the same signature on a different chain:

    - The DOMAIN_SEPARATOR on the new chain will have a different chainId.

    - The computed digest will not match the original signed digest.

    - ecrecover(digest, signature) will return address(0) or an incorrect signer, causing the permit to revert.
    - The burnFrom bug is also fixed and no user can circumvent the access control to burn tokens using the Oz burnFrom().
  
# DSCENGINE
- frob in makerDAO is simply deposit/withdraw collateral and mint/burn DSC here
- This contract defines the rules under which vaults/debt positions and balances can be manipulated.
- No debt ceiling in collateral type
- Minimum amount to mint is set - this guarantees that liquidations remain economically viable and efficient. 

# Collateral Types
- struct to hold collateral data parameters
- DSEngine - access controlled
- configure collateral type only doable by Admin.
- Cannot modify configuration is previously set.
- Admin can remove collateral configuration/support but only if there is no debt associated with that collateral. Removing means resetting the collateral config and also removing it from the allowed collateral ids array - some gem but gas intensive on this one too.

## Minting
- DSC is minted directly to the caller
- No third party support like in MakerDAO where a user can choose where to send generated Dai tokens in my system, it is assumed that such support the user can utilize the DSC contract functions to move their tokens however they want because it is a fully compliant erc20. 

## Liquidation Threshold
The idea behind the “adjusted collateral” is to capture the fact that in a worst‐case liquidation scenario you won’t actually be able to use 100% of your collateral’s current market value. Instead, you only “trust” a fraction of that value to cover the debt. Let me explain with an analogy and then break it down:

When you apply a liquidation threshold (for example, if LIQUIDATION_THRESHOLD is 50 and LIQUIDATION_PRECISION is 100), you’re effectively saying that only 50% of the raw collateral value is “trusted” to back the debt.
---

### **Analogy**

Imagine you have a house that you’ve pledged as collateral for a loan. In normal times, the house might be worth \$300,000. However, if you have to sell it quickly (say, in a market downturn), you might only be able to get 80% of its market value—about \$240,000. 

- **Total Market Value:** \$300,000  
- **“Trusted” Value in a Panic Sale:** \$240,000

Now, when the lender evaluates your safety, they won’t look at the full \$300,000—they’ll look at \$240,000 because that’s what they could realistically recover if they had to liquidate.  

Similarly, in many stablecoin systems, the protocol doesn’t use the entire collateral value; it applies a “liquidation threshold” (or safety buffer). In your code, that’s done by multiplying by something like LIQUIDATION_THRESHOLD/LIQUIDATION_PRECISION. For example, if LIQUIDATION_THRESHOLD is 50 (with LIQUIDATION_PRECISION 100), the protocol is effectively “trusting” only 50% of the collateral’s value.

---

### **Why Not Just Check Total Collateral to DSC?**

- **Without the Buffer:**  
  If you simply checked total collateral value against DSC minted, you might say, “Great, my collateral covers my debt 2:1, so I’m safe.”  
- **But in Reality:**  
  You need to account for potential losses in value during a liquidation. Not all of that collateral can be counted on to cover the debt if the market turns sour.  
- **The Safety Buffer:**  
  The adjusted collateral (for example, totalCollateralValueInUSD * (LIQUIDATION_THRESHOLD/LIQUIDATION_PRECISION)) tells you what portion of your collateral the system “trusts” to cover your debt. If that trusted value, when divided by the debt, falls below 1 (or your set minimum health factor), then the position is considered undercollateralized—even if the raw numbers (total collateral / DSC minted) look acceptable.

---

### **Key Points**

- **Risk Management:**  
  The adjusted value reflects the realistic amount you can recover in a liquidation event. It’s a conservative measure designed to protect the protocol and its users.

- **Effective Collateral Backing:**  
  Checking total collateral might give a false sense of security because it assumes a perfect market sale. The adjusted collateral is a way to say, “Even if I had to liquidate under less-than-ideal conditions, do I still have enough to cover the debt?”

- **Undercollateralization Check:**  
  By comparing the ratio of this adjusted (or “trusted”) collateral to the debt, the protocol ensures that even under adverse conditions the collateral backing remains sufficient. If the ratio falls below the required threshold, the vault is deemed undercollateralized and becomes eligible for liquidation.

---

### **Summary**

- **Why Use Adjusted Collateral?**  
  It reflects a realistic, conservative valuation of collateral during stressful market conditions. It’s not that overcollateralization isn’t maintained—rather, it’s a risk control measure that ensures that only the portion of the collateral that’s realistically liquidatable is used to secure the debt.

- **Why Not Just Total Collateral / DSC?**  
  Because that might overestimate your “real” collateral backing the debt. The safety buffer (adjusted collateral) is critical to ensure that even in a downturn, there’s enough value to cover the stablecoin debt.

This is why your function uses the adjusted collateral value in calculating the health factor. It’s not simply a mathematical twist—it’s a deliberate design choice to incorporate a safety margin that protects both the protocol and its users.


## Auctioning underwater positions
- will use linear decrease but the minimum  price at max duration for auction will not be hitting zero. WIll come up with a mechanimsm to determine maybe a percentage drop of the initial price. - some good reads on liquidation : https://blog.amberdata.io/performing-liquidations-on-makerdao


### Liquidations
#### Principles
1.  Time-Decaying Collateral Discount - from 3% decaying down to 1.8% in 1 hour so linear decrease.

Goal: Incentivize rapid liquidations to minimize protocol risk.

Discount Applied to Collateral, Not Debt

Scenario: A position has 100 DSC debt (pegged to 1)backed by collateral worth 150.

  Undercollateralization: Collateral value drops to $140 (<150% of debt).

Liquidation Process:

  Liquidator repays the full debt (100 DSC, worth $100).

  In return, they receive collateral worth $100 + discount (e.g., $110 for a 10% discount).

Profit: Liquidator sells the collateral for $110 → $10 profit.

Why This Works:

- The protocol recovers the full debt (100 DSC).

- Liquidators profit from the discounted collateral, not from underpaying the debt.

Time-Decaying Discount

Mechanics:

  Initial Discount: Starts at a high value (e.g., 15%) when the position is first undercollateralized.

  Linear Decay: Discount decreases over time (e.g., to 5% after 1 hour).

  Example:

  T+0: 15% discount → Liquidator receives $115 collateral for repaying $100 debt.

  T+30min: 10% discount → $110 collateral.

  T+60min: 5% discount → $105 collateral.

Risks Mitigated by this principle
Protocol Insolvency Risk

  By encouraging immediate liquidation, the protocol avoids further collateral value drops (e.g., from 140→120), which could leave the debt undercollateralized.

Liquidator Inaction

  A decaying discount creates a race-to-liquidate: Early liquidators earn higher rewards, while latecomers get smaller discounts.

Market Volatility

  Rapid liquidations reduce exposure to volatile collateral prices.

Documentation snippet
### Liquidation Mechanism  
When a position becomes undercollateralized (e.g., collateral value < 150% of debt), liquidators are incentivized to repay the debt in full (`100 DSC`) in exchange for collateral at a **discounted rate**.  

- **Discount Structure**:  
  - Starts at 15% and linearly decays to 5% over 1 hour.  
  - Example: Repaying `$100` debt yields `$115` collateral initially, decreasing to `$105` after 1 hour.  

- **Purpose**:  
  - Ensures debt is fully repaid while rewarding liquidators for acting swiftly.  
  - Protects the protocol from prolonged exposure to undercollateralized positions.  

Key Constraint: Rewards (discounts) are capped by the available collateral to prevent over-penalization.
Thus, 

DISCOUNT = MIN(TIME-BASED DISCOUNT, (Collateral VALUE / DSC DEBT)-1)

The second discount calctulation makes sure the max discount availableis only up to what the user who has been liquidated has on their collateral locked value. Even when the discount is larger percentage than available collateral value.

To avoid losing precision, the calculation above is scaled up using 1e18 before dividing with debt and then the 1 is also scaled to 1e18 so that the calculation is brought down to percentage numbers.

so the formula for the available max discount

(Collateral X PRECISION of 1e18)/Debt - 1e18

--need a function to calculatemaxdiscount()
-- minmimumoftwovalues()

### Precision Handling  
All values (collateral, debt, discounts) are scaled by `1e18` to avoid truncation:  
- **Example**: $140 → `140e18`, 10% → `0.1e18`.  
- **Max Discount**: `(collateral * 1e18 / debt) - 1e18`.  

2. Risk-Adjusted Liquidator Rewards

To prioritize liquidation of larger debt positions (higher systemic risk) while ensuring smaller positions remain attractive, use a scaled reward system based on debt size.
- Using the "clamped linear" model or also called piecewise linear model.
- This model is governed by the formula - Reward = min(max(k × Debt, R_min), R_max)
- where:
  - k (the Proportionality Constant):
This value represents the fraction of the debt that you’ll give as a reward. For instance, if k is 0.05 (or 5%), a debt of 1,000 units would yield a reward of 50 units. In DeFi protocols, liquidation bonuses often hover in the 5–10% range. So you might choose k around 0.05 to 0.1, depending on how aggressive you want the incentive to be.
  - R_min (Minimum Reward):
This is a floor to ensure that even very small liquidations are worthwhile for liquidators. The idea is to cover basic costs (like gas fees) so that the effort is always compensated. On networks like Ethereum, where gas can be expensive, a typical minimum might be in the range of 10–20 stable coin units (or an equivalent value) so that liquidators are motivated even when the debt is small.
- R_max (Maximum Reward):
This cap prevents the reward from growing without bounds when the debt is very large. It’s a safeguard against over-incentivizing the liquidation of huge positions, which might distort system dynamics. Drawing inspiration from protocols like MakerDAO or Compound—where penalties or incentives rarely exceed a certain percentage of the collateral or debt—you might set R_max to a value that, for example, limits rewards to the equivalent of a 5–10% bonus on a “typical” large liquidation. In practice, values might range anywhere from a few hundred to a thousand stable coin units, depending on the typical debt sizes and your risk management goals.

For this project, the following values are used:

For collateral with less than 150% overcollateralization: k = 0.5% (0.005)

For collateral with 150% or more overcollateralization: k = 1.5% (0.015) -- Liquidators receive a higher k when the collateral is riskier (150% and above), which aligns with the need to compensate for higher volatility.

R_min: A reward equivalent to $10 (10 dsc) -- Setting a minimum reward ensures that even the smallest debt positions (limited to 100 dsc) offer a sufficient incentive. For a 100 dsc debt, the computed reward would be very low (0.5 or 1.5 dsc), so bumping it to $10 is necessary to cover gas fees and make liquidations worthwhile. Although this means small positions have a high effective reward percentage, it’s a known and accepted trade-off in many protocols.

R_max: 5000 dsc (or $5000) -- The cap of 5000 dsc ensures that no matter how large the debt, the reward doesn’t spiral out of control. For very large positions, even though the raw calculation would yield a much higher bonus, the cap keeps the payout predictable.

For instance, under a 110% requirement, the reward reaches 5000 dsc only at around 1,000,000 dsc in debt.
Under a 150% requirement, the cap is hit at an even lower debt level (around 333,333 dsc) because of the higher k.
This design is common to prevent excessive incentives that could destabilize the system. If your protocol expects many high-debt positions, you might consider a slight increase in R_max, but be cautious: raising it too much can lead to over-incentivization and potential abuse.

-- For the smallest allowed debt, the computed reward (k × Debt) is less than the minimum. Therefore, the system always awards the minimum of 10 dsc. This helps ensure liquidators cover the cost (like gas fees) even for very small positions.

-- For very large debt positions (whether in the millions or billions), the computed reward would normally be huge. However, thanks to the R_max cap, the reward never exceeds 5000 dsc. This prevents runaway incentives and ensures that the reward stays within a controlled, predictable range.

## Fees
Protocol fees 1% APR (annual percentage rate)
Liquidation penalty - 2%