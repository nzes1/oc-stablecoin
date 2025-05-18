---
hide_title: true
sidebar_label: Minting and Redeeming DSC
toc_min_heading_level: 2
toc_max_heading_level: 6

---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

<Tabs queryString="minting-redeeming-dsc">
<TabItem value="mint-redeem" label="Minting and Redeeming DSC" default >

## Minting and Redeeming DSC

The core function of the protocol involves the issuance of its ERC20 stablecoin, DSC, when users supply supported collateral. To retrieve their locked collateral, users subsequently burn an equivalent amount of DSC.

## Minting DSC

Minting new DSC is a permissionless process, but it is always collateralized. Users must deposit crypto assets approved by the protocol (e.g., Ether, ERC20 tokens) to mint new DSC. This mechanism ensures the algorithmic and decentralized stability of DSC, which is pegged to the US Dollar.

The DSC token itself is a fully compliant ERC20 token, inheriting standard functionalities. Furthermore, it implements EIP-2612 widely known as [ERC20Permit](https://eips.ethereum.org/EIPS/eip-2612), enabling gasless token approvals for certain interactions.

### Key aspects of minting

The key aspects governing the minting of DSC are:

*   <details> 

    <summary>Collateral Backed</summary>

    Every DSC token in circulation is backed by an over-collateralized amount of approved assets.
    </details>

*   <details> 

    <summary>DSCEngine Control</summary>

    The `DSCEngine` smart contract exclusively manages the minting and burning of DSC. Users interact with wrapper functions within the `DSCEngine` to perform these actions (see [Link to Minting and Burning Interface Functions Section])
    </details>

*   <details> 

    <summary>Vault Creation</summary>

    Minting DSC against collateral initiates the creation of a collateral vault owned by the user.
    </details>

*   <details> 

    <summary>Over-Collateralization Checks</summary>

    Before DSC is minted, the protocol verifies that the value of the DSC requested does not exceed the allowed amount based on the deposited collateral and the collateral's over-collateralization ratio. This check is often referred to as the vault's "health factor."
    </details>

#### Example of Over-Collateralization

Consider a collateral type with a set over-collateralization ratio of 150%. If a user deposits \$150 worth of this collateral, the maximum amount of DSC they can mint is \$100 (since DSC is pegged 1:1 to USD). An attempt to mint, for example, 110 DSC against this \$150 collateral would fail as it violates the 150% over-collateralization requirement.

#### Pre-calculation of Max Mintable DSC

For user convenience, especially within a user interface (UI), the maximum mintable DSC for a given collateral amount can be pre-calculated off-chain. This calculation relies on the specific collateral's configuration parameters (e.g., price feed data, over-collateralization ratio).

#### Importance of a Safety Buffer

It is strongly advisable that users do not mint the maximum allowable DSC against their collateral vaults. Minting at the very edge of the over-collateralization ratio leaves the vault vulnerable to liquidation in the event of even minor price fluctuations in the collateral asset. Established DeFi protocols like MakerDAO recommend maintaining a significant buffer to safeguard against such risks.

*Example of a Safety Buffer*

> For instance, if the maximum mintable DSC for a $150 Ether collateral (at 150% over-collateralization) is 100 DSC, a user might choose to only mint 60-80 DSC. This 20-40 DSC difference acts as a buffer to absorb potential price drops in Ether without immediately risking liquidation. The ideal buffer size depends on the volatility of the collateral asset and the user's risk tolerance.

#### Protocol Fees (Minting and Redeeming)

The protocol currently charges a fee of 1% APR (Annual Percentage Rate) on the outstanding DSC debt. This fee accrues over time while the vault is open.

*Example of Fee Calculation*

> If a user mints 100 DSC and keeps their vault open for one year, they will accrue a fee of 1 DSC (1% of 100 DSC). If they keep it open for 6 months, the fee would be approximately 0.5 DSC (1% / 2). The exact fee calculation considers the time the DSC is outstanding. More detailed information on fee structures can be found in the [Link to Fees Docs Section].

#### Helper Functions for Collateral Valuation

The protocol provides helper functions that leverage Chainlink oracles to determine the current USD value of supported collateral assets. These functions can assist users in their pre-calculations and risk assessment. Details on these functions can be found in the [Link to Developer Interface Functions Section].

### Redeeming Collateral (Burning DSC)

The process of redeeming locked collateral involves the user paying back the full amount of DSC they owe to the protocol *for a specific vault*.

> (*While a user can repay a portion of their debt for a vault at any time, the withdrawal of the backing collateral will only be possible once all the DSC debt associated with that particular vault has been repaid in full.*)

Upon full repayment of the DSC debt for a vault, that amount of DSC is burned, permanently reducing the total supply. The user then receives the collateral they initially deposited into that specific vault back, minus any accrued protocol fees.

#### Key aspects of redeeming

*   <details> 

    <summary>DSCEngine Control</summary>

    Similar to minting, the `DSCEngine` contract manages the burning of DSC and the return of collateral. Users interact with wrapper functions within the `DSCEngine` ([Link to Minting and Burning Interface Functions Section]).
    </details>

*   <details> 

    <summary>Full DSC Repayment</summary>

    Users must repay the entire outstanding DSC amount associated with their vault to unlock and withdraw their collateral.
    </details>

*   <details> 

    <summary>Fee Deduction</summary>

    Unlike some other protocols (e.g., MakerDAO, where fees are paid in DAI), the fees in this protocol are deducted from the collateral being returned to the user.
    </details>

*   <details> 

    <summary>Partial or Full Repayment</summary>

    Users have the flexibility to burn a portion or all of the DSC they have minted against a specific vault. Burning DSC never negatively impacts the health factor of a vault; it only improves it by reducing the outstanding debt.
    </details>
</TabItem>

<TabItem value="ui-ux-functions" label="UI/UX User Functions">

## User Interface Functions: Minting and Redeeming DSC

This section outlines the primary functions within the `DSCEngine` contract that users can directly interact with to mint and redeem DSC.

### Minting Functions

```solidity
    /**
     * @notice Mints DSC against a specified amount of collateral.
     * @dev Allows users to lock existing deposited collateral and mint DSC.
     * @param collId The ID of the collateral token.
     * @param collAmt The amount of deposited collateral to lock.
     * @param dscAmt The amount of DSC to mint against the locked collateral.
     */
    function mintDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) external;

    /*//////////////////////////////////////////////////////////////
                        OTHER MINTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// The following functions also result in the minting of DSC and are further
    /// detailed within the Collateral Mechanism Docs Section:
    
    function depositCollateralAndMintDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) external;

    function depositEtherCollateralAndMintDSC(uint256 dscAmt) external payable;

    function expandETHVault(uint256 dscAmt) external payable;

    function expandVault(bytes32 collId, uint256 collAmt, uint256 dscAmt) external;

```

### Redeeming/Burning Functions

```solidity
    /**
     * @notice Burns a specified amount of DSC from the user's vault.
     * @dev Decreases the DSC debt associated with the user's vault.
     *  Fees are also settled prior to reducing the debt.
     * @param collId The ID of the collateral token.
     * @param dscAmt The amount of DSC to burn.
     */
    function burnDSC(bytes32 collId, uint256 dscAmt) external;

    /*//////////////////////////////////////////////////////////////
                   OTHER REDEEMING-RELATED FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// The following function also results in the burning of DSC and is further detailed
    /// within the Collateral Mechanism Docs Section:

    function redeemCollateralForDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) external;

```
</TabItem>

</Tabs>