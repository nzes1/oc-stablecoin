
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