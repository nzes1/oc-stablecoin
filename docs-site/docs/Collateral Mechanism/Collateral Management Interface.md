---
hide_title: true
---

<!-- ## User Interface : Collateral Management Functions -->

### Interacting with Collateral

This section details the functions within the protocol that users and administrators can directly interact with concerning collateral. These functions enable users to add and remove collateral, while administrators manage the supported collateral types.

### Adding Collateral

These functions allow any user to deposit collateral into the protocol. Some functions also enable users to deposit collateral and mint DSC stablecoins in a single transaction for efficiency.

    ```solidity
    /**
     * @notice Deposits Ether into the protocol as collateral for the sender.
     * @dev Accepts Ether via msg.value and updates the sender's collateral balance.
     * @dev The function is payable and public to enable direct Ether transfers.
     */
    function addEtherCollateral() external payable;

     /**
     * @notice Deposits ERC20 collateral into the protocol.
     * @dev Updates the user's available collateral balance tracked by the protocol.
     * @param collId   //emit The ID of the collateral token.
     * @param amount The amount of collateral to deposit.
     */
    function depositCollateral(bytes32 collId, uint256 amount) external;

    /**
     * @notice Deposits ERC20 collateral and mints DSC in a single transaction.
     * @dev Requires prior token approval. Reverts if collateral amount is zero or unsupported.
     * Ensures atomicity for vault creation and DSC issuance, enhancing user experience.
     * @param collId The ID of the collateral token.
     * @param collAmt The amount of collateral to deposit.
     * @param dscAmt The amount of DSC to mint against the deposited collateral.
     */
    function depositCollateralAndMintDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) external;

    /**
     * @notice Deposits Ether collateral and mints DSC in a single transaction.
     * @dev Requires the caller to send Ether. Reverts if the amount is zero.
     * Ensures atomicity for vault creation and DSC issuance, enhancing user experience.
     * @param dscAmt The amount of DSC to mint against the deposited Ether collateral.
     */
    function depositEtherCollateralAndMintDSC(uint256 dscAmt) external payable;

    /**
     * @notice Expands an existing Ether vault by adding Ether collateral and minting additional DSC.
     * @dev Requires the caller to send Ether. Reverts if the amount is zero.
     * Ensures atomic execution of Ether deposit and DSC minting for better UX.
     * @param dscAmt The amount of DSC to mint against the deposited Ether collateral.
     */
    function expandETHVault(uint256 dscAmt) external payable;

    /**
     * @notice Expands an existing vault by adding collateral and minting additional DSC.
     * @dev Requires prior token approval and valid collateral. Reverts if inputs are invalid.
     * Ensures atomic execution of collateral deposit and DSC minting for better UX.
     * @param collId The ID of the collateral token.
     * @param collAmt The amount of collateral to deposit.
     * @param dscAmt The amount of DSC to mint.
     */
    function expandVault(bytes32 collId, uint256 collAmt, uint256 dscAmt) external;

    /**
     * @notice Increases the locked collateral in an existing vault.
     * @dev Transfers collateral from the user's balance into the vault, boosting its backing.
     * @param collId The ID of the collateral type.
     * @param collAmt The amount of collateral to lock additionally in the vault.
     */
    function boostVault(bytes32 collId, uint256 collAmt) external;
    ```

### Removing Collateral

This section covers the functions that users can call to redeem or withdraw their collateral from the protocol. Certain functions facilitate closing entire vaults and retrieving the associated collateral, while others allow users to remove specific amounts of locked collateral from their vaults or withdraw collateral entirely from the protocol.

    ```solidity
    /**
     * @notice Redeems a specified amount of collateral from the vault.
     * @dev Allows users to withdraw collateral while maintaining their DSC debt.
     * @dev Healthy Health factor has to be maintained after redeeming.
     * @param collId The ID of the collateral token.
     * @param collAmt The amount of collateral to redeem.
     */
    function redeemCollateral(bytes32 collId, uint256 collAmt) external;

    /**
     * @notice Redeems locked collateral by burning DSC in a single transaction.
     * @dev Settles any protocol fees before redeeming. If full DSC debt is burned, the vault is considered closed,
     * and the user receives all remaining locked collateral instead of the specified amount.
     * @param collId The ID of the collateral token.
     * @param collAmt The amount of collateral to redeem.
     * @param dscAmt The amount of DSC to burn.
     */
    function redeemCollateralForDSC(bytes32 collId, uint256 collAmt, uint256 dscAmt) external;

    /**
     * @notice Withdraws a specified amount of collateral from the protocol.
     * @dev Requires the user to have sufficient collateral balance. Determines
     * if the collateral is Ether or ERC20 and processes the withdrawal accordingly.
     * @dev Emits a withdrawal event upon successful transfer.
     * @param collId The identifier of the collateral token.
     * @param amount The amount of collateral to withdraw.
     */
    function removeCollateral(bytes32 collId, uint256 amount) external;
    ```

### Collateral Information 

#### *Getter Functions*

These publicly accessible functions allow anyone to query and retrieve information related to collateral within the protocol. This includes details about supported collateral types, user balances, and configuration parameters.

    ```solidity
    /**
     * @notice Retrieves a list of all allowed collateral IDs in the protocol.
     * @return An array of collateral IDs.
     */
    function getAllowedCollateralIds() external view returns (bytes32[] memory);

    /**
     * @notice Fetches the address of the ERC20 collateral token for a given collateral ID.
     * @param collId The ID of the collateral.
     * @return The address of the collateral token.
     */
    function getCollateralAddress(bytes32 collId) external view returns (address);

    /**
     * @notice Retrieves the configuration settings for a specific collateral type.
     * @param collId The unique identifier for the collateral type.
     * @return The CollateralConfig struct containing the token address, total debt, liquidation threshold, and price
     * feed.
     */
    function getCollateralSettings(bytes32 collId) external view returns (Structs.CollateralConfig memory);

    /**
     * @notice Retrieves the collateral balance of a specific user for a given collateral type.
     * @dev Accesses the user's balance from the protocol's storage and is used to check how much collateral is
     * available for a user. i.e. unlocked collateral.
     * @param collId The ID of the collateral type.
     * @param user The address of the user.
     * @return The balance of the specified collateral type for the given user.
     */
    function getUserCollateralBalance(bytes32 collId, address user) external view returns (uint256);

    /**
     * @notice Calculates the USD value of the collateral locked in a vault.
     * @dev Fetches the current collateral price from the Chainlink price feed, scales it to 18 decimals,
     * and returns the value in USD. This value is essential for determining the Health Factor ratio and
     * the amount of DSC that can be minted against the collateral - the reason for scaling to 18 decimals.
     * @param collId The ID of the collateral type.
     * @param owner The address of the vault owner.
     * @return usdValue The USD value of the locked collateral, scaled to 18 decimals.
     */
    function getVaultCollateralUsdValue(bytes32 collId, address owner) external returns (uint256 usdValue);
    ```

### Administrative Functions

#### *Managing Collateral Support (`onlyOwner` Access)*

These functions, accessible only to the protocol owner (administrator), are used to configure and manage the protocol's support for different collateral types. This includes adding new collateral assets and removing existing ones.

    ```solidity
    /**
     * @notice Removes a collateral configuration from the protocol.
     * @dev This function can only be called by the contract owner. It will revert if there is any outstanding debt
     * associated with the collateral type. The removal will delete the configuration for the specified collateral.
     * @param collId The unique identifier for the collateral type to be removed.
     */
    function removeCollateralConfiguration(bytes32 collId) external;

    /**
     * @notice Configures a new collateral type with specified parameters.
     * @dev Only callable by the contract owner.
     * The function will revert if the collateral type has already been configured.
     * @param collId The unique identifier for the collateral type. e.g the token symbol.
     * @param tokenAddr The address of the ERC20 token contract representing the collateral.
     * @param liqThreshold The liquidation threshold as a percentage.
     * @param priceFeed The address of the Chainlink price feed for determining the collateral's USD value.
     * @param tknDecimals The number of decimals for the collateral token, ensuring proper scaling in calculations.
     */
    function configureCollateral(
        bytes32 collId,
        address tokenAddr,
        uint256 liqThreshold,
        address priceFeed,
        uint8 tknDecimals
    )
        external;
    ```
