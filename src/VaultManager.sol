// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Storage} from "./Storage.sol";
import {Structs} from "./Structs.sol";
import {OraclesLibrary} from "./libraries/OraclesLibrary.sol";
import {AggregatorV3Interface} from "@chainlink/contracts@v1.3.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20 as ERC20Like} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";

contract VaultManager is Storage {
    using OraclesLibrary for AggregatorV3Interface;

    // Creating a vault
    function createVault(
        bytes32 collId,
        uint256 collAmount,
        uint256 DSCAmount
    ) public {
        s_collBalances[collId][msg.sender] -= collAmount;

        s_vaults[collId][msg.sender].lockedCollateral += collAmount;
        s_vaults[collId][msg.sender].dscDebt += DSCAmount;
    }

    function boostVault(bytes32 collId, uint256 collAmount) public {
        s_collBalances[collId][msg.sender] -= collAmount;

        s_vaults[collId][msg.sender].lockedCollateral += collAmount;
    }

    function addToVault(
        bytes32 collId,
        uint256 collAmount,
        uint256 dscAmount
    ) public {
        s_collBalances[collId][msg.sender] -= collAmount;

        s_vaults[collId][msg.sender].lockedCollateral += collAmount;
        s_vaults[collId][msg.sender].dscDebt += dscAmount;
    }

    // function shrinkVault(
    //     bytes32 collId,
    //     address owner,
    //     uint256 collAmount,
    //     uint256 DSCAmount
    // ) public {
    //     s_collBalances[collId][owner] += collAmount;

    //     s_vaults[collId][owner].lockedCollateral -= collAmount;
    //     s_vaults[collId][owner].dscDebt -= DSCAmount;
    // }

    function shrinkVaultDebt(
        bytes32 collId,
        address owner,
        uint256 DSCAmount
    ) internal {
        s_vaults[collId][owner].dscDebt -= DSCAmount;
    }

    function shrinkVaultCollateral(
        bytes32 collId,
        uint256 collAmount
    ) internal {
        s_collBalances[collId][msg.sender] += collAmount;

        s_vaults[collId][msg.sender].lockedCollateral -= collAmount;
    }

    function isVaultHealthy(
        bytes32 collId,
        address owner
    ) internal returns (bool safe, uint256 healthFactor) {
        // ratio of coll -> dscdebt for this coll
        // get coll value and compare to debt
        // ratio should be at minimum the configured liquidation ratio for this coll

        // Balance of DSC debt
        uint256 vaultDebt = s_vaults[collId][owner].dscDebt;

        // No debt the vault is infinitely healthy
        if (vaultDebt == 0) {
            return (true, type(uint256).max);
        }

        // Get coll value
        uint256 vaultCollBalUsd = getVaultCollateralUsdValue(collId, owner);

        // HF = ratio of trusted/ backing coll to debt
        // Needs to be more than minHF which is always 1e18 - the assumption here is that
        // the ratio of the collateral that the protocol considers as the safety margin or rather
        // cover of loan is the maximum you can mint dsc. this value will yield a ratio of 1 and
        // any amounts greater than this max amount breaks the ratio below 1. Minting less than the
        // max dsc for the locked collateral means hf is above 1 hence healthy.
        // both have 18 decimals i.e. the coll in usd and DSC
        // To maintain the decimals for the health factor, then the result needs to be
        // scaled up with 18 decimals. The ratio automatically  removes the decimals.
        // SO scalling result up is like (vaultCollBalUsd / vaultDebt) * 18decimals.
        // But it's always recommended to do multiplication before division so that you
        // don't lose precision due to division.
        // so that changes to (vaultCollBalUsd * 18decimals / vaultDebt)
        uint256 trustedVaultCollUsd = (vaultCollBalUsd *
            s_collaterals[collId].liquidationThresholdPercentage) /
            LIQUIDATION_PRECISION;

        uint256 healthFactorRatio = (trustedVaultCollUsd * PRECISION) /
            vaultDebt;

        return (healthFactor >= MIN_HEALTH_FACTOR, healthFactorRatio);
    }

    function getVaultCollateralUsdValue(
        bytes32 collId,
        address owner
    ) public returns (uint256 usdValue) {
        uint256 vaultBal;
        uint256 rawUsdValue;
        uint256 scaledUpUsdValue;

        vaultBal = s_vaults[collId][owner].lockedCollateral;
        rawUsdValue = getRawUsdValue(collId, vaultBal);

        scaledUpUsdValue = scaleUsdValueToDSCDecimals(collId, rawUsdValue);

        return scaledUpUsdValue;
    }

    function getRawUsdValue(
        bytes32 collId,
        uint256 amount
    ) public view returns (uint256 rawUsdValue) {
        // Decimals of collaterals => to use in rep one token of the collateral
        uint8 collDecimals = s_tokenDecimals[collId];

        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_collaterals[collId].priceFeedAddr
        );

        (, int256 price, , , ) = priceFeed.latestRoundDataStalenessCheck();

        // raw USD value = (amount * price) / 10 ** colldecimals
        // The idea is that one token is represented as 10^(tokenDecimals).
        // i.e. usdValueOfTokens = (amountOfTokens * oraclePrice) / oneTokenInFullDecimalsForThatToken;

        // USD value that is scaled relative to the oracle’s decimals.
        rawUsdValue = (amount * uint256(price)) / (10 ** collDecimals);

        return (rawUsdValue);
    }

    function scaleUsdValueToDSCDecimals(
        bytes32 collId,
        uint256 rawUsdValue
    ) public returns (uint256 scaledUsdValue) {
        uint8 oracleDecimals;

        // only fetch decimals if not saved and cache it if not cached moving forward.
        if (!s_oracleDecimals[collId].cached) {
            AggregatorV3Interface priceFeed = AggregatorV3Interface(
                s_collaterals[collId].priceFeedAddr
            );

            oracleDecimals = priceFeed.decimals();

            s_oracleDecimals[collId].cached = true;
            s_oracleDecimals[collId].decimals = oracleDecimals;
        } else {
            oracleDecimals = s_oracleDecimals[collId].decimals;
        }

        // Scale up if oracle decimals are lower than DSC's 18.
        if (oracleDecimals < DSC_DECIMALS) {
            scaledUsdValue =
                rawUsdValue *
                (10 ** (DSC_DECIMALS - oracleDecimals));

            return scaledUsdValue;
        }

        // If they are the same, no scaling is necessary.
        return rawUsdValue;
    }
}
