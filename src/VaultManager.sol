// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Storage} from "./Storage.sol";
import {Structs} from "./Structs.sol";
import {OraclesLibrary} from "./libraries/OraclesLibrary.sol";
import {AggregatorV3Interface} from "@chainlink/contracts@v1.3.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20 as ERC20Like} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";

import {console} from "forge-std/console.sol";

contract VaultManager is Storage {

    using OraclesLibrary for AggregatorV3Interface;

    function boostVault(bytes32 collId, uint256 collAmt) external {
        s_collBalances[collId][msg.sender] -= collAmt;

        s_vaults[collId][msg.sender].lockedCollateral += collAmt;
    }

    // Creating a vault
    function createVault(bytes32 collId, uint256 collAmt, uint256 dscAmt) internal {
        s_collBalances[collId][msg.sender] -= collAmt;

        s_vaults[collId][msg.sender].lockedCollateral += collAmt;
        s_vaults[collId][msg.sender].dscDebt += dscAmt;
        s_vaults[collId][msg.sender].lastUpdatedAt = block.timestamp;
    }

    function shrinkVaultDebt(bytes32 collId, address owner, uint256 dscAmt) internal {
        s_vaults[collId][owner].dscDebt -= dscAmt;
        s_vaults[collId][owner].lastUpdatedAt = block.timestamp;
    }

    function shrinkVaultCollateral(bytes32 collId, uint256 collAmt) internal {
        s_collBalances[collId][msg.sender] += collAmt;

        s_vaults[collId][msg.sender].lockedCollateral -= collAmt;
    }

    function vaultDetails(bytes32 collId, address owner) internal view returns (uint256 collAmt, uint256 dscDebt) {
        collAmt = s_vaults[collId][owner].lockedCollateral;
        dscDebt = s_vaults[collId][owner].dscDebt;
    }

    function isVaultHealthy(bytes32 collId, address owner) internal returns (bool safe, uint256 healthFactor) {
        // ratio of coll -> dsc debt for this coll
        // get coll value and compare to debt
        // ratio should be at minimum 1e18

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
        // SO scaling result up is like (vaultCollBalUsd / vaultDebt) * 18decimals.
        // But it's always recommended to do multiplication before division so that you
        // don't lose precision due to division.
        // so that changes to (vaultCollBalUsd * 18decimals / vaultDebt)
        uint256 trustedVaultCollUsd = (vaultCollBalUsd * s_collaterals[collId].liqThreshold) / PRECISION;

        uint256 healthFactorRatio = (trustedVaultCollUsd * PRECISION) / vaultDebt;

        return (healthFactorRatio >= MIN_HEALTH_FACTOR, healthFactorRatio);
    }

    function getVaultCollateralUsdValue(bytes32 collId, address owner) public returns (uint256 usdValue) {
        uint256 vaultBal;
        uint256 rawUsdValue;
        uint256 scaledUpUsdValue;

        vaultBal = s_vaults[collId][owner].lockedCollateral;
        rawUsdValue = getRawUsdValue(collId, vaultBal);

        scaledUpUsdValue = scaleUsdValueToDSCDecimals(collId, rawUsdValue);

        return scaledUpUsdValue;
    }

    function getRawUsdValue(bytes32 collId, uint256 amount) public view returns (uint256 rawUsdValue) {
        // Decimals of collaterals => to use in rep one token of the collateral
        uint8 collDecimals = s_tokenDecimals[collId];

        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_collaterals[collId].priceFeed);

        (, int256 price,,,) = priceFeed.latestRoundDataStalenessCheck();

        // raw USD value = (amount * price) / 10 ** coll decimals
        // The idea is that one token is represented as 10^(tokenDecimals).
        // i.e. usdValueOfTokens = (amountOfTokens * oraclePrice) / oneTokenInFullDecimalsForThatToken;

        // USD value that is scaled relative to the oracle’s decimals.
        rawUsdValue = (amount * uint256(price)) / (10 ** collDecimals);

        return rawUsdValue;
    }

    function scaleUsdValueToDSCDecimals(
        bytes32 collId,
        uint256 rawUsdValue
    )
        internal
        returns (uint256 scaledUsdValue)
    {
        uint8 oracleDecimals;

        // only fetch decimals if not saved and cache it if not cached moving forward.
        if (!s_oracleDecimals[collId].cached) {
            AggregatorV3Interface priceFeed = AggregatorV3Interface(s_collaterals[collId].priceFeed);

            oracleDecimals = priceFeed.decimals();

            s_oracleDecimals[collId].cached = true;
            s_oracleDecimals[collId].decimals = oracleDecimals;
        } else {
            oracleDecimals = s_oracleDecimals[collId].decimals;
        }

        // Scale up if oracle decimals are lower than DSC's 18.
        if (oracleDecimals < DSC_DECIMALS) {
            scaledUsdValue = rawUsdValue * (10 ** (DSC_DECIMALS - oracleDecimals));

            return scaledUsdValue;
        }

        // If they are the same, no scaling is necessary.
        return rawUsdValue;
    }

    function getTokenAmountFromUsdValue2(bytes32 collId, uint256 usdValue) public returns (uint256 tokenAmount) {
        // The formula for getting the token amount is the opposite for getting usd value
        // given price P, usd value as U and decimals as D:
        // 1 token will be represented as 1D which means 1eD 1 expressed in the decimals
        // and price given is for  1 token
        // Then P = 1D
        //      U = ??
        // (U * 1D ) / P where P maintains it's decimals.
        // But since the USD value that will be coming here especially during liquidation will
        // already be scaled up to DSC decimals, then the price needs to be scaled up to 18 decimals too.
        uint8 collDecimals = s_tokenDecimals[collId];

        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_collaterals[collId].priceFeed);

        (, int256 price,,,) = priceFeed.latestRoundDataStalenessCheck();

        // First scale price to match decimals of the value being inputted
        uint256 scaledUpPrice = scaleUsdValueToDSCDecimals(collId, uint256(price));

        tokenAmount = (usdValue * (10 ** collDecimals)) / scaledUpPrice;

        return tokenAmount;
    }

}
