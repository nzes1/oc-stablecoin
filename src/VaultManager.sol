// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Storage} from "./Storage.sol";
import {Structs} from "./Structs.sol";
import {OraclesLibrary} from "./libraries/OraclesLibrary.sol";
import {AggregatorV3Interface} from "@chainlink/contracts@v1.3.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20 as ERC20Like} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";

import {console} from "forge-std/console.sol";
/**
 * @title VaultManager
 * @author Nzesi
 * @notice Handles the core logic for managing user vaults including creation, collateral adjustments, and debt
 * tracking.
 * @dev This contract manages collateral balances and enforces proper accounting between globally deposited
 * collateral and vault-specific locked balances. It provides utilities for computing vault
 * health, valuation in USD, and conversions between collateral tokens and USD value.
 *
 * @dev Key Responsibilities:
 * - Opening vaults by locking collateral and minting DSC
 * - Boosting or shrinking vault collateral and DSC debt
 * - Tracking vault collateral and debt positions
 * - Evaluating vault health based on collateral-to-debt ratio
 * - Providing pricing and value conversion helpers
 */

contract VaultManager is Storage {

    using OraclesLibrary for AggregatorV3Interface;

    /**
     * @notice Increases the locked collateral in an existing vault.
     * @dev Transfers collateral from the user's balance into the vault, boosting its backing.
     * @param collId The ID of the collateral type.
     * @param collAmt The amount of collateral to lock additionally in the vault.
     */
    function boostVault(bytes32 collId, uint256 collAmt) external {
        s_collBalances[collId][msg.sender] -= collAmt;

        s_vaults[collId][msg.sender].lockedCollateral += collAmt;
    }

    /**
     * @notice Creates a new vault by locking collateral and minting DSC.
     * @dev Initializes the vault for the user with specified collateral and DSC debt.
     * Updates user collateral balance, vault locked collateral, and debt records.
     * @param collId The ID of the collateral type.
     * @param collAmt The amount of collateral to lock in the vault.
     * @param dscAmt The amount of DSC to mint against the locked collateral.
     */
    function createVault(bytes32 collId, uint256 collAmt, uint256 dscAmt) internal {
        s_collBalances[collId][msg.sender] -= collAmt;

        s_vaults[collId][msg.sender].lockedCollateral += collAmt;
        s_vaults[collId][msg.sender].dscDebt += dscAmt;
        s_vaults[collId][msg.sender].lastUpdatedAt = block.timestamp;
    }

    /**
     * @notice Reduces the DSC debt of a vault.
     * @dev Deducts DSC from the vault’s debt and updates the last fee accrual timestamp.
     * @param collId The ID of the collateral type.
     * @param owner The address of the vault owner.
     * @param dscAmt The amount of DSC to remove from the vault's debt.
     */
    function shrinkVaultDebt(bytes32 collId, address owner, uint256 dscAmt) internal {
        s_vaults[collId][owner].dscDebt -= dscAmt;
        s_vaults[collId][owner].lastUpdatedAt = block.timestamp;
    }

    /**
     * @notice Reduces the locked collateral in a vault.
     * @dev Increases the user's collateral balance and decreases the vault's locked collateral.
     * @param collId The ID of the collateral type.
     * @param collAmt The amount of collateral to unlock from the vault.
     */
    function shrinkVaultCollateral(bytes32 collId, uint256 collAmt) internal {
        s_collBalances[collId][msg.sender] += collAmt;
        s_vaults[collId][msg.sender].lockedCollateral -= collAmt;
    }

    /**
     * @notice Returns the locked collateral and DSC debt of a vault.
     * @param collId The ID of the collateral type.
     * @param owner The address of the vault owner.
     * @return collAmt The collateral amount locked in the vault.
     * @return dscDebt The outstanding DSC debt of the vault.
     */
    function vaultDetails(bytes32 collId, address owner) internal view returns (uint256 collAmt, uint256 dscDebt) {
        collAmt = s_vaults[collId][owner].lockedCollateral;
        dscDebt = s_vaults[collId][owner].dscDebt;
    }

    /**
     * @notice Determines if a vault is healthy based on its collateral and debt ratio.
     * @dev The health factor is calculated by comparing the collateral value (in USD) with the DSC debt, using a
     * trusted collateral ratio. A vault is considered healthy if the health factor is greater than or equal to
     * the minimum required health factor (1e18).
     * The health factor is scaled to 18 decimals for precision. If the vault's debt is zero, it is automatically
     * considered healthy.
     * @param collId The ID of the collateral type.
     * @param owner The address of the vault owner.
     * @return safe A boolean indicating if the vault is healthy (true) or undercollateralized (false).
     * @return healthFactor The health factor ratio of the vault, scaled to 18 decimals.
     */
    function isVaultHealthy(bytes32 collId, address owner) internal returns (bool safe, uint256 healthFactor) {
        uint256 vaultDebt = s_vaults[collId][owner].dscDebt;

        if (vaultDebt == 0) {
            return (true, type(uint256).max);
        }

        uint256 vaultCollBalUsd = getVaultCollateralUsdValue(collId, owner);
        uint256 trustedVaultCollUsd = (vaultCollBalUsd * s_collaterals[collId].liqThreshold) / PRECISION;

        uint256 healthFactorRatio = (trustedVaultCollUsd * PRECISION) / vaultDebt;

        return (healthFactorRatio >= MIN_HEALTH_FACTOR, healthFactorRatio);
    }

    /**
     * @notice Calculates the USD value of the collateral locked in a vault.
     * @dev Fetches the current collateral price from the Chainlink price feed, scales it to 18 decimals,
     * and returns the value in USD. This value is essential for determining the Health Factor ratio and
     * the amount of DSC that can be minted against the collateral - the reason for scaling to 18 decimals.
     * @param collId The ID of the collateral type.
     * @param owner The address of the vault owner.
     * @return usdValue The USD value of the locked collateral, scaled to 18 decimals.
     */
    function getVaultCollateralUsdValue(bytes32 collId, address owner) public returns (uint256 usdValue) {
        uint256 vaultBal;
        uint256 rawUsdValue;
        uint256 scaledUpUsdValue;

        vaultBal = s_vaults[collId][owner].lockedCollateral;
        rawUsdValue = getRawUsdValue(collId, vaultBal);
        scaledUpUsdValue = scaleUsdValueToDSCDecimals(collId, rawUsdValue);

        return scaledUpUsdValue;
    }

    /**
     * @notice Returns the raw USD value of a specified amount of collateral.
     * @dev Fetches the current collateral price from the Chainlink price feed and calculates
     * the USD value based on the amount. The result is in the same scale as the price feed's decimals,
     * not scaled to 18 decimals.
     * @param collId The ID of the collateral type.
     * @param amount The amount of collateral to convert to USD value.
     * @return rawUsdValue The raw USD value of the specified collateral amount.
     */
    function getRawUsdValue(bytes32 collId, uint256 amount) public view returns (uint256 rawUsdValue) {
        uint8 collDecimals = s_tokenDecimals[collId];

        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_collaterals[collId].priceFeed);
        (, int256 price,,,) = priceFeed.latestRoundDataStalenessCheck();
        rawUsdValue = (amount * uint256(price)) / (10 ** collDecimals);

        return rawUsdValue;
    }

    /**
     * @notice Scales the raw USD value to match DSC's 18 decimal format.
     * @dev Adjusts the USD value based on the price feed's decimals to ensure consistency with DSC,
     * which uses 18 decimals.
     * @dev Assumes feed decimals do not exceed 18.
     * @param collId The ID of the collateral type.
     * @param rawUsdValue The raw USD value to be scaled.
     * @return scaledUsdValue The USD value scaled to 18 decimals.
     */
    function scaleUsdValueToDSCDecimals(
        bytes32 collId,
        uint256 rawUsdValue
    )
        internal
        returns (uint256 scaledUsdValue)
    {
        uint8 oracleDecimals;

        if (!s_oracleDecimals[collId].cached) {
            AggregatorV3Interface priceFeed = AggregatorV3Interface(s_collaterals[collId].priceFeed);
            oracleDecimals = priceFeed.decimals();
            s_oracleDecimals[collId].cached = true;
            s_oracleDecimals[collId].decimals = oracleDecimals;
        } else {
            oracleDecimals = s_oracleDecimals[collId].decimals;
        }

        if (oracleDecimals < DSC_DECIMALS) {
            scaledUsdValue = rawUsdValue * (10 ** (DSC_DECIMALS - oracleDecimals));

            return scaledUsdValue;
        }

        return rawUsdValue;
    }

    /**
     * @notice Converts a USD value to the equivalent amount of collateral tokens.
     * @dev Uses the collateral's price and decimal precision to compute the token amount
     * that corresponds to the given USD value. Price is scaled to 18 decimals for consistency.
     * @param collId The ID of the collateral type.
     * @param usdValue The USD value to convert.
     * @return tokenAmount The corresponding amount of collateral tokens.
     */
    function getTokenAmountFromUsdValue(bytes32 collId, uint256 usdValue) public returns (uint256 tokenAmount) {
        uint8 collDecimals = s_tokenDecimals[collId];

        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_collaterals[collId].priceFeed);
        (, int256 price,,,) = priceFeed.latestRoundDataStalenessCheck();
        uint256 scaledUpPrice = scaleUsdValueToDSCDecimals(collId, uint256(price));

        tokenAmount = (usdValue * (10 ** collDecimals)) / scaledUpPrice;

        return tokenAmount;
    }

}
