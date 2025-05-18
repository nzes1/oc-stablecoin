---
hide_title: true

---

## Design

Modularity is a core principle of this protocol, with contracts separated to enhance maintainability, facilitate upgrades, and improve readability. 

The `CollateralManager.sol` file contains the `CollateralManager` contract, which handles collateral deposits and withdrawals for the `DSCEngine` protocol. This contract supports both native Ether and ERC20 token collateral. It also tracks individual user collateral balances and enforces the protocol's collateral logic. The `DSCEngine` contract inherits the `CollateralManager` contract.

Users can interact with the protocol by calling specific functions within the `DSCEngine`, which, in turn, make internal calls to functions managing collateral deposits and withdrawals within the `CollateralManager` contract. An exception exists for adding Ether as collateral, where the function is public and directly callable without going through the `DSCEngine`. The same applies when removing collateral.
