---
hide_title: true
sidebar_label: Liquidation Interface
toc_min_heading_level: 2
toc_max_heading_level: 6
---

## Liquidation Interface Functions

This section outlines the user-facing functions available within the `DSCEngine` contract that are directly related to the liquidation process. These functions allow anyone to identify and liquidate undercollateralized vaults, contributing to the protocol's stability.

There are two primary functions users can interact with for liquidations:

1. `markVaultAsUnderwater()`
2. `liquidateVault()`

The two functions are explained below together with their parameters:

```solidity
/**
     * @notice Flags a vault as underwater and optionally initiates liquidation.
     * @dev Intended for use by governance or keeper bots. Can be used to only mark or both mark and liquidate.
     * @param collId The ID of the vault collateral token.
     * @param owner The address of the vault owner.
     * @param liquidate Whether to proceed with liquidation immediately.
     * @param dsc The amount of DSC to repay if liquidating.
     * @param withdraw Whether to withdraw the proceeds of liquidation from the protocol or not. This flexibility gives
     * liquidators the option to keep the collateral within the protocol for future use such as opening new vaults
     * themselves.
     */
    function markVaultAsUnderwater(
        bytes32 collId,
        address owner,
        bool liquidate,
        uint256 dsc,
        bool withdraw
    )
        external;

        /**
     * @notice Executes the liquidation of an unhealthy vault by repaying its DSC debt and seizing collateral.
     * @dev This is the core liquidation function responsible for handling the mechanics of an undercollateralized
     * vault.
     * It can be called by anyone, but the caller must supply the vault's amount of DSC to repay the debt.
     *
     * If the vault was not previously marked as underwater, the function will first flag it and apply the more generous
     * liquidation reward parameters, providing greater incentive to the liquidator. These reward mechanics are defined
     * in the Liquidation contract and ensure that early liquidators receive a premium.
     *
     * The function processes the liquidation in the following order:
     * 1. Applies a liquidation penalty, deducted from the vault owner’s locked collateral.
     * 2. Calculates liquidation rewards for the liquidator based on the DSC repaid.
     * 3. Burns the DSC supplied by the liquidator and charges protocol fees (also deducted from the owner's
     * collateral).
     *
     * Liquidation outcomes fall into one of three categories:
     *
     * 1. Sufficient Collateral for Full Liquidation:
     *    The vault has enough collateral to cover both the base repayment (i.e., collateral equivalent of DSC debt)
     *    and the calculated liquidation rewards. The liquidator receives both in full.
     *
     * 2. Partial Rewards:
     *    The vault has enough to repay the base DSC-equivalent collateral but not the full rewards.
     *    The liquidator receives the base and as much of the rewards as available. If the remaining collateral
     *    is only sufficient for base repayment, then rewards may be zero.
     *
     * 3. Insufficient Collateral (Bad Debt):
     *    The vault doesn't have enough collateral to repay even the base amount. The liquidator receives no collateral.
     *    Instead, the DSC they repaid is refunded by minting new DSC from the protocol to cover their loss.
     *    The protocol absorbs the bad debt and takes ownership of the vault. Once governance is implemented, custom
     *    rules and resolutions can be introduced to handle absorbed bad debt positions.
     *
     * If the liquidator opts to withdraw (`withdraw = true`), their rewards are sent to their address.
     * If not, the seized collateral remains in the protocol, credited to their internal balance for future use.
     *
     * Any excess collateral left after repaying DSC and rewards is returned to the vault owner.
     *
     * @param collId The ID of the collateral token.
     * @param owner The address of the vault owner.
     * @param dscToRepay The amount of DSC the liquidator is repaying to initiate liquidation.
     * @param withdraw Whether the liquidator wants to immediately withdraw the received collateral from the protocol.
     */
    function liquidateVault(bytes32 collId, address owner, uint256 dscToRepay, bool withdraw) external;
```