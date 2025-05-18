---
hide_title: true
sidebar_label: Contracts ABI
toc_min_heading_level: 2
toc_max_heading_level: 6
---

::::warning Important Note on Collateral Balance

Throughout this ABI documentation, the term "collateral balance" may refer to two distinct concepts within the protocol:

1. ***Global User Collateral Balance -*** This represents the total amount of a specific collateral type held by a user within the protocol, outside of any specific DSC vault. This balance increases upon depositing collateral that is not directly tied to minting DSC.
2. ***Locked Collateral (Vault Balance) -*** This refers to the amount of a specific collateral type that is actively backing DSC within a user's individual vault. Certain actions, such as boosting a vault's collateralization, may draw from the user's global collateral balance to increase the locked collateral within that vault.

:::tip 
Please pay close attention to the context of "collateral balance" within each function's description to understand whether it pertains to the user's global balance or the locked balance within a DSC vault.
:::
::::

### addEtherCollateral

Deposits Ether into the protocol as collateral for the sender.

*Accepts Ether via msg.value and updates the sender's collateral balance.*

*The function is payable and public to enable direct Ether transfers.*


```solidity
function addEtherCollateral() public payable;
```

<details>

<summary><b>Events (Emits) and Errors</b></summary>

**Emits**

|Name|Parameters|Description|
|----|-----------|-----------|
|`CM__CollateralDeposited`|`address indexed depositor`, `string collId` (`"ETH"`), `uint256 depositAmount`|Emitted when Ether collateral is successfully deposited by a user.|

**Errors**

|Name|Parameters|Description|
|----|-----------|-----------|
|`CM__ZeroAmountNotAllowed`||Thrown if the ether deposit amount is zero.|

</details>

### depositCollateral

Deposits ERC20 collateral into the protocol.

*Updates the user's available collateral balance tracked by the protocol.*


```solidity
function depositCollateral(bytes32 collId, uint256 amount) public nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|  The ID of the collateral token.|
|`amount`|`uint256`|The amount of collateral to deposit.|

<details>

<summary><b>Events (Emits) and Errors</b></summary>

**Emits**

|Name|Parameters|Description|
|----|-----------|-----------|
|`CM__CollateralDeposited`|`string collId`, `address indexed depositor`, `uint256 collAmt`|Emitted when collateral is successfully deposited.|

**Errors**

|Name|Parameters|Description|
|----|-----------|-----------|
|`CM__ZeroAmountNotAllowed`||Thrown if the provided deposit amount is zero.|
|`CM__CollateralTokenNotApproved`||Thrown if the collateral token has not been approved for use as collateral in the protocol.|
|`Collateral Deposit Failed`||Thrown if the transfer of collateral from the depositor to the protocol fails.|

</details>


### depositEtherCollateralAndMintDSC

Deposits Ether collateral and mints DSC in a single transaction.

*Requires the caller to send Ether. Reverts if the amount is zero.
Ensures atomicity for vault creation and DSC issuance, enhancing user experience.*


```solidity
function depositEtherCollateralAndMintDSC(uint256 dscAmt) external payable isValidDebtSize(dscAmt);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dscAmt`|`uint256`|The amount of DSC to mint against the deposited Ether collateral.|

<details>

<summary><b>Events (Emits) and Errors</b></summary>

**Emits**

|Name|Parameters|Description|
|----|-----------|-----------|
|`CM__CollateralDeposited`|`address indexed depositor`, `string collId` (`"ETH"`), `uint256 depositAmount`|Emitted when Ether collateral is successfully deposited.|
|`DscMinted`|`address indexed minter`, `uint256 dscAmt`| Emitted when DSC is successfully minted.|

**Errors**

|Name|Parameters|Description|
|----|-----------|-----------|
|`DSCEngine__DebtSizeBelowMinimumAmountAllowed`|`uint256 minDebt`|(Via modifier) Thrown if the resulting debt would be below the protocol's minimum debt amount of 100 DSC.|
|`CM__ZeroAmountNotAllowed`|| Thrown if the deposit amount is zero.|
|`CM__AmountExceedsCurrentBalance`|`string collId`, `uint256 available`| Thrown if the deposit amount exceeds the user's available global Ether collateral balance.|
|`DSCEngine__HealthFactorBelowThreshold`|`uint256 healthFactor`| Thrown if the user's health factor would fall below the safe threshold after minting.|
|`DSCEngine__MintingDSCFailed`|| Thrown if the DSC ERC20 contract returns false during the DSC minting process.|

</details>

### depositCollateralAndMintDSC

Deposits ERC20 collateral and mints DSC in a single transaction.

*Requires prior token approval. Reverts if collateral amount is zero or unsupported.
Ensures atomicity for vault creation and DSC issuance, enhancing user experience.*


```solidity
function depositCollateralAndMintDSC(
    bytes32 collId,
    uint256 collAmt,
    uint256 dscAmt
)
    external
    isValidDebtSize(dscAmt);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the collateral token.|
|`collAmt`|`uint256`|The amount of collateral to deposit.|
|`dscAmt`|`uint256`|The amount of DSC to mint against the deposited collateral.|

<details>

<summary><b>Events (Emits) and Errors</b></summary>

**Emits**

|Name|Parameters|Description|
|----|-----------|-----------|
|`CM__CollateralDeposited`|`string collId`, `address indexed depositor`, `uint256 collAmt`|Emitted when collateral is successfully deposited.|
|`DscMinted`|`address indexed minter`, `uint256 dscAmt`|Emitted when DSC is successfully minted.|

**Errors**

|Name|Parameters|Description|
|----|-----------|-----------|
|`CM__ZeroAmountNotAllowed`||Thrown if the provided deposit amount is zero.|
|`CM__CollateralTokenNotApproved`||Thrown if the collateral token has not been approved for use in the protocol.|
|`Collateral Deposit Failed`||Thrown if collateral transfer from depositor to the protocol fails.|
|`DSCEngine__HealthFactorBelowThreshold`|`uint256 healthFactor`|Thrown if the user's health factor would fall below the safe threshold of 1 after minting.|
|`DSCEngine__MintingDSCFailed`||Thrown if the DSC minting process fails.|
|`DSCEngine__DebtSizeBelowMinimumAmountAllowed`|`uint256 minDebt`|Thrown if the resulting debt would be below the protocol's minimum debt amount (100 DSC).|

</details>

### boostVault

Increases the locked collateral in an existing vault.

*Transfers collateral from the user's balance into the vault, boosting its backing.*


```solidity
function boostVault(bytes32 collId, uint256 collAmt) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the collateral type.|
|`collAmt`|`uint256`|The amount of collateral to lock additionally in the vault.|

### expandVault

Expands an existing vault by adding collateral and minting additional DSC.

*Requires prior token approval and valid collateral. Reverts if inputs are invalid.
Ensures atomic execution of collateral deposit and DSC minting for better UX.*


```solidity
function expandVault(bytes32 collId, uint256 collAmt, uint256 dscAmt) external isValidDebtSize(dscAmt);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the collateral token.|
|`collAmt`|`uint256`|The amount of collateral to deposit.|
|`dscAmt`|`uint256`|The amount of DSC to mint.|

<details>

<summary><b>Events (Emits) and Errors</b></summary>

**Emits**

|Name|Parameters|Description|
|----|-----------|-----------|
|`CM__CollateralDeposited`|`string collId`, `address indexed depositor`, `uint256 collAmt`|Emitted when additional collateral is deposited into the user's global balance.|
|`DscMinted`|`address indexed minter`, `uint256 dscAmt`|Emitted when additional DSC is minted against the vault's collateral.|

**Errors**

|Name|Parameters|Description|
|----|-----------|-----------|
|`DSCEngine__HealthFactorBelowThreshold`|`uint256 healthFactor`|Thrown if adding the specified collateral and minting the additional DSC would cause the vault's health factor to fall below the minimum threshold (1).|
|`DSCEngine__MintingDSCFailed`||Thrown if the DSC minting process fails.|
|`CM__ZeroAmountNotAllowed`||Thrown if the provided collateral deposit amount is zero.|
|`CM__CollateralTokenNotApproved`||Thrown if the collateral token has not been approved for use as collateral in the protocol.|
|`Collateral Deposit Failed`||Thrown if the collateral transfer from the user to the protocol fails.|

</details>


### expandETHVault

Expands an existing Ether vault by adding Ether collateral and minting additional DSC.

*Requires the caller to send Ether. Reverts if the amount is zero.
Ensures atomic execution of Ether deposit and DSC minting for better UX.*


```solidity
function expandETHVault(uint256 dscAmt) external payable isValidDebtSize(dscAmt);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dscAmt`|`uint256`|The amount of DSC to mint against the deposited Ether collateral.|

<details>

<summary><b>Events (Emits) and Errors</b></summary>

**Emits**

|Name|Parameters|Description|
|----|-----------|-----------|
|`CM__CollateralDeposited`|`string collId` (`"ETH"`), `address indexed depositor`, `uint256 depositAmount`|Emitted when additional Ether collateral is deposited into the user's global balance.|
|`DscMinted`|`address indexed minter`, `uint256 dscAmt`|Emitted when additional DSC is minted against the vault's collateral.|

**Errors**

|Name|Parameters|Description|
|----|-----------|-----------|
|`DSCEngine__HealthFactorBelowThreshold`|`uint256 healthFactor`|Thrown if adding the specified Ether collateral and minting the additional DSC would cause the vault's health factor to fall below the minimum threshold (1).|
|`DSCEngine__MintingDSCFailed`||Thrown if the DSC minting process fails.|
|`CM__ZeroAmountNotAllowed`||Thrown if the provided Ether deposit amount is zero.|

</details>

### redeemCollateral

Redeems a specified amount of collateral from the vault.

*Allows users to withdraw collateral while maintaining their DSC debt.*

*Healthy Health factor has to be maintained after redeeming.*


```solidity
function redeemCollateral(bytes32 collId, uint256 collAmt) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the collateral token.|
|`collAmt`|`uint256`|The amount of collateral to redeem.|

<details>

<summary><b>Events (Emits) and and Errors</b></summary>

**Emits**

|Name|Parameters|Description|
|----|-----------|-----------|
|`CM__CollateralWithdrawn`|`string collId`, `address indexed caller`, `uint256 amount`|Emitted when collateral is successfully withdrawn.|

**Errors**

|Name|Parameters|Description|
|----|-----------|-----------|
|`DSCEngine__HealthFactorBelowThreshold`|`uint256 healthFactor`|Thrown if redeeming the specified amount of collateral would cause the user's health factor to fall below the minimum threshold (1).|
|`CM__ZeroAmountNotAllowed`||Thrown if the requested redemption amount is zero.|
|`CM__AmountExceedsCurrentBalance`|`string collId`, `uint256 available`|Thrown if the requested redemption amount exceeds the user's available global collateral balance for the specified collateral type.|
|`Ether Transfer Failed`||Thrown if the transfer of Ether to the user fails during the collateral redemption process.|

</details>


### redeemCollateralForDSC

Redeems locked collateral by burning DSC in a single transaction.

*Settles any protocol fees before redeeming. If full DSC debt is burned, the vault is considered closed,
and the user receives all remaining locked collateral instead of the specified amount.*


```solidity
function redeemCollateralForDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the collateral token.|
|`collAmt`|`uint256`|The amount of collateral to redeem.|
|`dscAmt`|`uint256`|The amount of DSC to burn.|

<details>

<summary><b>Events (Emits) and Errors</b></summary>

**Emits**

|Name|Parameters|Description|
|----|-----------|-----------|
|`CM__CollateralWithdrawn`|`string collId`, `address indexed caller`, `uint256 amount`|Emitted when collateral is successfully withdrawn/redeemed.|

**Errors**

|Name|Parameters|Description|
|----|-----------|-----------|
|`DSCEngine__BurningDSCFailed`||Thrown if the burning of DSC fails (e.g., DSC transfer back from the user to the DSEngine fails).|
|`DSCEngine__HealthFactorBelowThreshold`|`uint256 healthFactor`|Thrown if removing the locked collateral would cause the user's health factor to fall below the minimum threshold (1).|
|`CM__AmountExceedsCurrentBalance`|`string collId`, `uint256 available`|Thrown if the requested withdrawal amount exceeds the user's available global collateral balance for the specified collateral type.|
|`Ether Transfer Failed`||Thrown if the transfer of Ether to the user fails during the redemption process.|

</details>

### removeCollateral

Withdraws a specified amount of collateral from the protocol.

*Requires the user to have sufficient collateral balance. Determines
if the collateral is Ether or ERC20 and processes the withdrawal accordingly.*

*Emits a withdrawal event upon successful transfer.*


```solidity
function removeCollateral(bytes32 collId, uint256 amount) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The identifier of the collateral token.|
|`amount`|`uint256`|The amount of collateral to withdraw.|

<details>

<summary><b>Events (Emits) and Errors</b></summary>

**Emits**

|Name|Parameters|Description|
|----|-----------|-----------|
|`CM__CollateralWithdrawn`|`string collId`, `address indexed caller`, `uint256 amount`|Emitted when a user successfully withdraws collateral.|

**Errors**

|Name|Parameters|Description|
|----|-----------|-----------|
|`CM__ZeroAmountNotAllowed`||Thrown if the requested withdrawal amount is zero.|
|`CM__AmountExceedsCurrentBalance`|`string collId`, `uint256 available`|Thrown if the requested withdrawal amount exceeds the user's available global collateral balance for the specified collateral type.|
|`Ether Transfer Failed`||Thrown if the internal Ether transfer during the withdrawal process fails. (Note: This is a string revert, so parameters might not be explicitly available in the ABI)|

</details>


### mintDSC

Mints DSC against a specified amount of collateral.

*Allows users to lock existing deposited collateral and mint DSC.*


```solidity
function mintDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) public isValidDebtSize(dscAmt) nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the collateral token.|
|`collAmt`|`uint256`|The amount of deposited collateral to lock.|
|`dscAmt`|`uint256`|The amount of DSC to mint against the locked collateral.|

<details>

<summary><b>Events (Emits) and and Errors</b></summary>

**Emits**

|Name|Parameters|Description|
|----|-----------|-----------|
|`DscMinted`|`address indexed minter`, `uint256 dscAmt`|Emitted when DSC is successfully minted.|

**Errors**

|Name|Parameters|Description|
|----|-----------|-----------|
|`DSCEngine__DebtSizeBelowMinimumAmountAllowed`|`uint256 minDebt`|Thrown if the resulting debt would be below the protocol's minimum debt amount (100 DSC).|
|`DSCEngine__HealthFactorBelowThreshold`|`uint256 healthFactor`|Thrown if the user's health factor would fall below the safe threshold after minting the requested DSC amount.|
|`DSCEngine__MintingDSCFailed`||Thrown if the DSC minting process fails.|

</details>

### burnDSC

Burns a specified amount of DSC from the user's vault.

*Decreases the DSC debt associated with the user's vault.
Fees are also settled prior to reducing the debt.*


```solidity
function burnDSC(bytes32 collId, uint256 dscAmt) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the collateral token.|
|`dscAmt`|`uint256`|The amount of DSC to burn.|

<details>

<summary><b>Events (Emits) and and Errors</b></summary>

**Errors**

|Name|Parameters|Description|
|----|-----------|-----------|
|`DSCEngine__BurningDSCFailed`||Thrown if the burning of DSC fails.|

</details>


### calculateFees

Calculates the protocol fee based on the specified debt amount and time duration.

*This function computes the fee using a fixed annual percentage rate (APR), prorated over the provided
debt period. The fee represents the cost of maintaining an open debt position within the protocol.*


```solidity
function calculateFees(uint256 debt, uint256 debtPeriod) external pure returns (uint256);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`debt`|`uint256`|The outstanding DSC debt for which the fee is to be calculated.|
|`debtPeriod`|`uint256`|The duration (in seconds) over which the debt has been active.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|fee The total protocol fee owed for the specified debt and period.|


### markVaultAsUnderwater

Flags a vault as underwater and optionally initiates liquidation.

*Intended for use by governance or keeper bots. Can be used to only mark or both mark and liquidate.*


```solidity
function markVaultAsUnderwater(bytes32 collId, address owner, bool liquidate, uint256 dsc, bool withdraw) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the vault collateral token.|
|`owner`|`address`|The address of the vault owner.|
|`liquidate`|`bool`|Whether to proceed with liquidation immediately.|
|`dsc`|`uint256`|The amount of DSC to repay if liquidating.|
|`withdraw`|`bool`|Whether to withdraw the proceeds of liquidation from the protocol or not. This flexibility gives liquidators the option to keep the collateral within the protocol for future use such as opening new vaults themselves.|

<details>

<summary><b>Events (Emits) and Errors</b></summary>

**Emits**

|Name|Parameters|Description|
|----|-----------|-----------|
|`VaultMarkedAsUnderwater`|`string collId`, `address indexed owner`|Emitted when a vault is marked as underwater due to its health factor falling below the critical threshold.|
|`LiquidationWithFullRewards`|`string collId`, `address indexed owner`, `address indexed liquidator`|Emitted when a vault is fully liquidated, and the liquidator receives the full liquidation rewards.|
|`LiquidationWithPartialRewards`|`string collId`, `address indexed owner`, `address indexed liquidator`|Emitted when a vault is partially liquidated, and the liquidator receives partial liquidation rewards.|
|`AbsorbedBadDebt`|`string collId`, `address indexed owner`|Emitted when the protocol absorbs bad debt from a vault because liquidations could not cover the base equivalent of the debt.|
|`LiquidationSurplusReturned`|`string collId`, `address indexed owner`, `uint256 surplus`|Emitted when surplus collateral remains after a liquidation and is returned to the vault owner.|
|`CM__CollateralWithdrawn`|`string collId`, `address indexed caller`, `uint256 amount`|Emitted when collateral is withdrawn by the liquidator from the protocol as part of the liquidation process.|

**Errors**

|Name|Parameters|Description|
|----|-----------|-----------|
|`DSCEngine__VaultNotUnderwater`||Thrown if an attempt is made to mark a vault as underwater when its health factor is not below the critical threshold.|
|`LM__VaultNotLiquidatable`||Thrown if an attempt is made to liquidate a vault that is not currently eligible for liquidation (e.g., its health factor is not sufficiently low).|
|`LM__SuppliedDscNotEnoughToRepayBadDebt`||Thrown if the amount of DSC supplied by the liquidator is not sufficient to cover the vault's full DSC debt.|
|`DSCEngine__BurningDSCFailed`||Thrown if the burning of DSC (debt repayment) fails during the liquidation process.|
|`CM__ZeroAmountNotAllowed`||Thrown if a zero amount is provided for a collateral withdrawal.|
|`CM__AmountExceedsCurrentBalance`|`string collId`, `uint256 available`|Thrown if the liquidator attempts to withdraw more global collateral than they currently hold.|
|`Ether Transfer Failed`||Thrown if the transfer of Ether to the liquidator fails during the liquidation process.|

</details>

### calculateLiquidationRewards

Calculates the liquidation rewards for a liquidator based on vault details.

*Rewards are calculated in DSC and are based on the size of the debt and the speed
of liquidation. A time-decaying discount is applied based on how long the vault has been
underwater. The final rewards are returned in DSC, which is pegged to USD and will be
converted to collateral amount for transfer in the DSCEngine.*


```solidity
function calculateLiquidationRewards(bytes32 collId, address owner) public view returns (uint256 rewards);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the vault collateral type.|
|`owner`|`address`|The address of the vault owner.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`rewards`|`uint256`|The total liquidation rewards in USD.|


### liquidateVault

Executes the liquidation of an unhealthy vault by repaying its DSC debt and seizing collateral.

*This is the core liquidation function responsible for handling the mechanics of an undercollateralized
vault.
It can be called by anyone, but the caller must supply the vault's amount of DSC to repay the debt.
If the vault was not previously marked as underwater, the function will first flag it and apply the more generous
liquidation reward parameters, providing greater incentive to the liquidator. These reward mechanics are defined
in the Liquidation contract and ensure that early liquidators receive a premium.
The function processes the liquidation in the following order:
1. Applies a liquidation penalty, deducted from the vault owner’s locked collateral.
2. Calculates liquidation rewards for the liquidator based on the DSC repaid.
3. Burns the DSC supplied by the liquidator and charges protocol fees (also deducted from the owner's
collateral).
Liquidation outcomes fall into one of three categories:
1. Sufficient Collateral for Full Liquidation:
The vault has enough collateral to cover both the base repayment (i.e., collateral equivalent of DSC debt)
and the calculated liquidation rewards. The liquidator receives both in full.
2. Partial Rewards:
The vault has enough to repay the base DSC-equivalent collateral but not the full rewards.
The liquidator receives the base and as much of the rewards as available. If the remaining collateral
is only sufficient for base repayment, then rewards may be zero.
3. Insufficient Collateral (Bad Debt):
The vault doesn't have enough collateral to repay even the base amount. The liquidator receives no collateral.
Instead, the DSC they repaid is refunded by minting new DSC from the protocol to cover their loss.
The protocol absorbs the bad debt and takes ownership of the vault. Once governance is implemented, custom
rules and resolutions can be introduced to handle absorbed bad debt positions.
If the liquidator opts to withdraw (`withdraw = true`), their rewards are sent to their address.
If not, the seized collateral remains in the protocol, credited to their internal balance for future use.
Any excess collateral left after repaying DSC and rewards is returned to the vault owner.*


```solidity
function liquidateVault(bytes32 collId, address owner, uint256 dscToRepay, bool withdraw) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the collateral token.|
|`owner`|`address`|The address of the vault owner.|
|`dscToRepay`|`uint256`|The amount of DSC the liquidator is repaying to initiate liquidation.|
|`withdraw`|`bool`|Whether the liquidator wants to immediately withdraw the received collateral from the protocol.|

<details>

<summary><b>Events (Emits) and Errors</b></summary>

**Emits**

|Name|Parameters|Description|
|----|-----------|-----------|
|`VaultMarkedAsUnderwater`|`string collId`, `address indexed owner`|Emitted when a vault is marked as underwater prior to liquidation.|
|`LiquidationWithFullRewards`|`string collId`, `address indexed owner`, `address indexed liquidator`|Emitted when a vault is fully liquidated, and the liquidator receives the full liquidation rewards.|
|`LiquidationWithPartialRewards`|`string collId`, `address indexed owner`, `address indexed liquidator`|Emitted when a vault is partially liquidated, and the liquidator receives partial liquidation rewards.|
|`AbsorbedBadDebt`|`string collId`, `address indexed owner`|Emitted when the protocol absorbs bad debt from a vault because liquidations could not cover the base equivalent of the debt.|
|`LiquidationSurplusReturned`|`string collId`, `address indexed owner`, `uint256 surplus`|Emitted when surplus collateral remains after a liquidation and is returned to the vault owner.|
|`CM__CollateralWithdrawn`|`string collId`, `address indexed caller`, `uint256 amount`|Emitted when collateral is withdrawn by the liquidator from the protocol as part of the liquidation process.|

**Errors**

|Name|Parameters|Description|
|----|-----------|-----------|
|`LM__VaultNotLiquidatable`||Thrown if an attempt is made to liquidate a vault that is not currently eligible for liquidation (e.g., its health factor is not sufficiently low).|
|`LM__SuppliedDscNotEnoughToRepayBadDebt`||Thrown if the amount of DSC supplied by the liquidator is not sufficient to cover the vault's bad debt.|
|`DSCEngine__BurningDSCFailed`||Thrown if the burning of DSC (debt repayment) fails during the liquidation process.|
|`CM__ZeroAmountNotAllowed`||Thrown if a zero amount is provided for a DSC repayment or collateral withdrawal.|
|`CM__AmountExceedsCurrentBalance`|`string collId`, `uint256 available`|Thrown if the liquidator attempts to withdraw more global collateral than they currently hold.|
|`Ether Transfer Failed`||Thrown if the transfer of Ether to the liquidator fails during the liquidation process.|

</details>


### getHealthFactor

Checks the health factor of a user's vault for a given collateral type.

*This function calls an internal helper function to evaluate the health factor of the user's vault.
It returns a boolean indicating whether the vault is healthy and the current health factor value.*


```solidity
function getHealthFactor(bytes32 collId, address user) external returns (bool, uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the collateral type.|
|`user`|`address`|The address of the vault owner.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|A boolean indicating whether the vault is healthy and the current health factor value.|
|`<none>`|`uint256`||


### getCollateralSettings

Retrieves the configuration settings for a specific collateral type.


```solidity
function getCollateralSettings(bytes32 collId) external view returns (Structs.CollateralConfig memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The unique identifier for the collateral type.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Structs.CollateralConfig`|The CollateralConfig struct containing the token address, total debt, liquidation threshold, and price feed.|


### getAllowedCollateralIds

Retrieves a list of all allowed collateral IDs in the protocol.


```solidity
function getAllowedCollateralIds() external view returns (bytes32[] memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32[]`|An array of collateral IDs.|


### getCollateralAddress

Fetches the address of the ERC20 collateral token for a given collateral ID.


```solidity
function getCollateralAddress(bytes32 collId) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the collateral.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the collateral token.|


### getVaultInformation

Retrieves the locked collateral amount and DSC debt for a specific vault.


```solidity
function getVaultInformation(bytes32 collId, address owner) external view returns (uint256 collAmt, uint256 dscDebt);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the collateral type.|
|`owner`|`address`|The address of the vault owner.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`collAmt`|`uint256`|The amount of collateral locked in the vault.|
|`dscDebt`|`uint256`|The amount of DSC debt associated with the vault.|


### getUserCollateralBalance

Retrieves the collateral balance of a specific user for a given collateral type.

*Accesses the user's balance from the protocol's storage and is used to check how much collateral is
available for a user. i.e. unlocked collateral.*


```solidity
function getUserCollateralBalance(bytes32 collId, address user) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the collateral type.|
|`user`|`address`|The address of the user.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The balance of the specified collateral type for the given user.|


### getTotalDscDebt

Retrieves the total DSC debt for a specific collateral type.


```solidity
function getTotalDscDebt(bytes32 collId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the collateral type.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The total DSC debt associated with the specified collateral type.|


### getVaultCollateralUsdValue

Calculates the USD value of the collateral locked in a vault.

*Fetches the current collateral price from the Chainlink price feed, scales it to 18 decimals,
and returns the value in USD. This value is essential for determining the Health Factor ratio and
the amount of DSC that can be minted against the collateral - the reason for scaling to 18 decimals.*


```solidity
function getVaultCollateralUsdValue(bytes32 collId, address owner) public returns (uint256 usdValue);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the collateral type.|
|`owner`|`address`|The address of the vault owner.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`usdValue`|`uint256`|The USD value of the locked collateral, scaled to 18 decimals.|


### getTokenAmountFromUsdValue

Converts a USD value to the equivalent amount of collateral tokens.

*Uses the collateral's price and decimal precision to compute the token amount
that corresponds to the given USD value. Price is scaled to 18 decimals for consistency.*


```solidity
function getTokenAmountFromUsdValue(bytes32 collId, uint256 usdValue) public returns (uint256 tokenAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the collateral type.|
|`usdValue`|`uint256`|The USD value to convert.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokenAmount`|`uint256`|The corresponding amount of collateral tokens.|


### getRawUsdValue

Returns the raw USD value of a specified amount of collateral.

*Fetches the current collateral price from the Chainlink price feed and calculates
the USD value based on the amount. The result is in the same scale as the price feed's decimals,
not scaled to 18 decimals.*


```solidity
function getRawUsdValue(bytes32 collId, uint256 amount) public view returns (uint256 rawUsdValue);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The ID of the collateral type.|
|`amount`|`uint256`|The amount of collateral to convert to USD value.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`rawUsdValue`|`uint256`|The raw USD value of the specified collateral amount.|

### latestRoundDataStalenessCheck

Verifies the freshness of the latest Chainlink price feed data.


```solidity
function latestRoundDataStalenessCheck(AggregatorV3Interface _priceFeed)
    public
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_priceFeed`|`AggregatorV3Interface`|The address of the Chainlink AggregatorV3Interface contract.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`roundId`|`uint80`|The ID of the latest data round.|
|`answer`|`int256`|The reported price from the latest round.|
|`startedAt`|`uint256`|Timestamp when the round was initiated.|
|`updatedAt`|`uint256`|Timestamp when the round was last updated.|
|`answeredInRound`|`uint80`|The round ID in which the answer was finalized.|

<details>

<summary><b>Errors</b></summary>

**Errors**

|Name|Parameters|Description|
|----|-----------|-----------|
|`OraclesLibrary__StalePriceFeed`||Thrown if the latest price data retrieved from the oracle is considered stale.|

</details>

### configureCollateral

Configures a new collateral type with specified parameters.

*Only callable by the contract owner.
The function will revert if the collateral type has already been configured.*


```solidity
function configureCollateral(
    bytes32 collId,
    address tokenAddr,
    uint256 liqThreshold,
    address priceFeed,
    uint8 tknDecimals
)
    public
    onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The unique identifier for the collateral type. e.g the token symbol.|
|`tokenAddr`|`address`|The address of the ERC20 token contract representing the collateral.|
|`liqThreshold`|`uint256`|The liquidation threshold as a percentage.|
|`priceFeed`|`address`|The address of the Chainlink price feed for determining the collateral's USD value.|
|`tknDecimals`|`uint8`|The number of decimals for the collateral token, ensuring proper scaling in calculations.|

<details>

<summary><b> Errors</b></summary>

**Errors**

|Name|Parameters|Description|
|----|-----------|-----------|
|`DSCEngine__CollateralConfigurationAlreadySet`|`string collId`|Thrown if an attempt is made to configure a collateral type that has already been configured.|

</details>

### removeCollateralConfiguration

Removes a collateral configuration from the protocol.

*This function can only be called by the contract owner. It will revert if there is any outstanding debt
associated with the collateral type. The removal will delete the configuration for the specified collateral.*


```solidity
function removeCollateralConfiguration(bytes32 collId) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collId`|`bytes32`|The unique identifier for the collateral type to be removed.|

<details>

<summary><b>Errors</b></summary>

**Errors**

|Name|Parameters|Description|
|----|-----------|-----------|
|`DSCEngine__CollateralConfigurationCannotBeRemovedWithOutstandingDebt`|`uint256 outstandingDebt`|Thrown if an attempt is made to remove a collateral configuration while there is still outstanding debt backed by that collateral type.|

</details>

