// SPDX-License-Identifier: MIT

/*//////////////////////////////////////////////////////////////
                            CONTRACT LAYOUT
//////////////////////////////////////////////////////////////*/

/**
 * @dev Contract Layout based on RareSkills Solidity Style guide
 * here: https://www.rareskills.io/post/solidity-style-guide which expounds on
 * Solidity's recommended guide on the docs.
 * Type Declarations
 * State Variables
 * Events
 * Errors
 * Modifiers
 * Constructor
 * receive
 * fallback
 * Functions:
 *  External
 *      External View
 *      External pure
 *  Public
 *      Public View
 *      Public pure
 *  Internal
 *      Internal View
 *      Internal Pure
 *  Private
 *      Private View
 *      Private Pure
 *
 */
pragma solidity 0.8.24;

import {IDSCEngine} from "./IDSCEngine.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts@5.1.0/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts@v1.3.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OraclesLibrary} from "./libraries/OraclesLibrary.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {CollateralManager} from "./CollateralManager.sol";
import {VaultManager} from "./VaultManager.sol";
import {Structs} from "./Structs.sol";
import {Storage} from "./Storage.sol";
import {Fees} from "./Fees.sol";
import {Liquidations} from "./Liquidation.sol";

contract DSCEngine is
    Storage,
    Ownable,
    Fees,
    ReentrancyGuard,
    CollateralManager,
    VaultManager,
    Liquidations
{
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    using OraclesLibrary for AggregatorV3Interface;

    /**
     * @dev Collateral data key parameters
     */

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev The address of the DSC token
     */
    DecentralizedStableCoin private immutable i_DSC;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event DscMinted(address indexed owner, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error DSCEngine__MintingDSCFailed();
    error DSCEngine__BurningDSCFailed();

    error DSCEngine__HealthFactorBelowThreshold(uint256 healthFactor);

    error DSCEngine__ZeroAmountNotAllowed();
    error DSCEngine__AccountNotLiquidatable();
    error DSCEngine__CollateralConfigurationAlreadySet(bytes32 collateralId);
    error DSCEngine__CollateralConfigurationCannotBeRemovedWithOutstandingDebt(
        uint256 debt
    );

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Modifier to check that the amount is more than zero.
     * @dev Reverts if the amount is zero.
     */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__ZeroAmountNotAllowed();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     *
     * @param tokenAddresses A list of addresses of the permitted collateral tokens.
     * @param priceFeedsAddresses A list of addresses of the chainlink USD price feeds
     * for the respective collateral tokens.
     * @param DSCTokenAddress The address of the DSC ERC20 token that uses the logic
     * defined in this engine contract.
     */
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedsAddresses,
        address DSCTokenAddress
    ) Ownable(msg.sender) {
        // if (tokenAddresses.length != priceFeedsAddresses.length) {
        //     revert DSCEngine__CollateralTokensAddressesAndPriceFeedsAddressesLengthMismatch();
        // }

        // for (uint256 k = 0; k < tokenAddresses.length; k++) {
        //     s_priceFeeds[tokenAddresses[k]] = priceFeedsAddresses[k];
        //     s_collateralTokens.push(tokenAddresses[k]);
        // }

        i_DSC = DecentralizedStableCoin(DSCTokenAddress);
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The function allows users to deposit collateral tokens and mint DSC tokens in
     * a single transaction.
     * @dev The user has to approve the transfer of the collateral tokens to this contract
     * prior to initiating the deposit.
     * @dev The amount the user deposits has to be more than zero. The token also has to be
     * allowed as collateral. The function reverts otherwise.
     * @param collId The address of the collateral token.
     * @param collAmount The amount of collateral tokens to deposit.
     * @param DSCAmount The amount of DSC tokens to mint.
     */
    function depositCollateralAndMintDSC(
        bytes32 collId,
        uint256 collAmount,
        uint256 DSCAmount
    ) external {
        depositCollateral(collId, collAmount);
        mintDSC(collId, collAmount, DSCAmount);
    }

    // need inheritance to avoid change of msg.sender
    function depositEtherCollateralAndMintDSC(
        uint256 DSCAmount
    ) external payable {
        addEtherCollateral();
        mintDSC("ETH", msg.value, DSCAmount);
    }

    function redeemCollateralForDSC(
        bytes32 collId,
        uint256 collAmount,
        uint256 DSCAmount
    ) external {
        // begin by burning to reduce debt
        // to avoid double check on hf, call directly the internal function.
        _burnDSC(collId, DSCAmount, msg.sender, msg.sender);

        // Then move the collateral specified, but only if hf is not broken
        redeemCollateral(collId, collAmount);
    }

    // to avoid circle inheritance, this function was moved from the VM contract to the engine here
    function addToVault(
        bytes32 collId,
        uint256 collAmount,
        uint256 dscAmount
    ) external {
        // to top -up debt, the accumulated fees has to be collected first.
        // then top-up the debt together with backing collateral

        // collect accumulated fees
        settleProtocolFees(
            collId,
            msg.sender,
            s_vaults[collId][msg.sender].dscDebt
        );

        // accounting updates
        s_collBalances[collId][msg.sender] -= collAmount;

        s_vaults[collId][msg.sender].lockedCollateral += collAmount;
        s_vaults[collId][msg.sender].dscDebt += dscAmount;
        s_vaults[collId][msg.sender].lastUpdatedAt = block.timestamp;

        // this block is repeated...maybe
        //HF of vault has to remain healthy
        (bool healthy, uint256 hf) = isVaultHealthy(collId, msg.sender);

        if (!healthy) {
            revert DSCEngine__HealthFactorBelowThreshold(hf);
        }

        // otherwise it is healthy so mint actual dsc to user
        // Mint DSC to user address
        bool mintStatus = i_DSC.mint(msg.sender, dscAmount);

        if (!mintStatus) {
            revert DSCEngine__MintingDSCFailed();
        }
        //emit
        emit DscMinted(msg.sender, dscAmount);
    }

    function liquidateVault(
        bytes32 collId,
        address owner,
        uint256 dscToRepay,
        bool withdraw
    ) public {
        // msg.sender is the liquidator
        address liquidator = msg.sender;
        // Initiate the liquidation
        initiateLiquidation(collId, dscToRepay, owner);

        // If above call does not revert, then supplied dsc is enough, take it from liquidator
        // and burn it; but first take liquidation penalty, calculate all rewards that are dependent
        // on dssc debt since burn will remove/close the debt from vault.

        // Settle penalty first
        settleLiquidationPenalty(collId, owner, dscToRepay);

        // Calculate rewards secondly
        uint256 liquidatorRewardsUsd = calculateLiquidationRewards(
            collId,
            owner
        );

        // calling internal _burnDSC automatically also charges the fees and collects them
        _burnDSC(collId, dscToRepay, owner, liquidator);

        // Get the collateral tokens equivalent of the rewards
        uint256 liquidatorTokens = getTokenAmountFromUsdValue2(
            collId,
            liquidatorRewardsUsd
        );

        // Base collateral liquidator should receive without rewards
        uint256 baseCollateral = getTokenAmountFromUsdValue2(
            collId,
            dscToRepay
        );

        uint256 totalPayout = baseCollateral + liquidatorTokens;

        // Transfer collateral + rewards to liquidator >>>
        // The transfer involves updating the internal treasury books
        // But if the liquidator has marked withdraw as true, then the transfer will
        // further do actual sending of the tokens out of the system.
        // Otherwise the balances will reflect inside the system giving the liquidator
        // the chance of say openening vaults of their own without having to redepeosit collateral.
        // If there is any excess, that will be for the vault owner

        uint256 vaultCollBal = s_vaults[collId][owner].lockedCollateral;

        // standard liquidation scenario where collateral is sufficient
        if (vaultCollBal >= totalPayout) {
            s_vaults[collId][owner].lockedCollateral -= totalPayout;
            s_collBalances[collId][liquidator] += totalPayout;
            //emit
        }
        // Partial rewards but full base collateral
        // Important to note that rewards can be zero here too!
        else if (vaultCollBal >= baseCollateral) {
            s_vaults[collId][owner].lockedCollateral -= vaultCollBal; // maybe just set to zero
            s_collBalances[collId][liquidator] += vaultCollBal;
            //emit
        }
        // Protocol absorbs the vault as bad debt
        else {
            delete s_vaults[collId][owner];
            s_absorbedBadVaults[collId][address(this)] = Structs.Vault({
                lockedCollateral: vaultCollBal,
                dscDebt: dscToRepay,
                lastUpdatedAt: block.timestamp
            });
            //emit
        }

        // Withdraw
        if (withdraw) {
            removeCollateral(collId, s_collBalances[collId][liquidator]);
        }

        // If there is surplus, increase the balance of liquidated vault owner
        uint256 surplus = s_vaults[collId][owner].lockedCollateral;
        if (surplus > 0) {
            s_vaults[collId][owner].lockedCollateral -= surplus;
            s_collBalances[collId][owner] += surplus;
        }
    }

    function markVaultAsUnderwater(
        bytes32 collId,
        address owner,
        bool liquidate,
        uint256 dsc,
        bool withdraw
    ) public {
        // check for underwater status and mark it
        vaultIsUnderwater(collId, owner);
        if (liquidate) {
            liquidateVault(collId, owner, dsc, withdraw);
        }
    }

    function depositCollateral(
        bytes32 collId,
        uint256 amount
    ) public nonReentrant {
        addCollateral(collId, amount);
    }

    function mintDSC(
        bytes32 collId,
        uint256 collAmt,
        uint256 dscAmt
    ) public moreThanZero(dscAmt) nonReentrant {
        // increase their debt first
        createVault(collId, collAmt, dscAmt);

        // Vault has to be overcollateralized as per the set configs for that collateral
        (bool healthy, uint256 healthFactor) = isVaultHealthy(
            collId,
            msg.sender
        );

        if (!healthy) {
            revert DSCEngine__HealthFactorBelowThreshold(healthFactor);
        }

        // Mint DSC to user address
        bool mintStatus = i_DSC.mint(msg.sender, dscAmt);

        if (!mintStatus) {
            revert DSCEngine__MintingDSCFailed();
        }
        //emit
        emit DscMinted(msg.sender, dscAmt);
    }

    function redeemCollateral(bytes32 collId, uint256 collAmount) public {
        _redeemVaultCollateral(collId, collAmount);
    }

    // no health check!!! --- problem because this is a public func--corrected
    function burnDSC(bytes32 collId, uint256 DSCAmount) public {
        _burnDSC(collId, DSCAmount, msg.sender, msg.sender);

        // revert if burning breaks HF
        (bool healthy, uint256 hf) = isVaultHealthy(collId, msg.sender);
        if (!healthy) {
            revert DSCEngine__HealthFactorBelowThreshold(hf);
        }
    }

    function _redeemVaultCollateral(
        bytes32 collId,
        uint256 collAmount
    ) internal {
        // shrinking shouldn't affect oc ratio
        shrinkVaultCollateral(collId, collAmount);

        (bool healthy, uint256 hf) = isVaultHealthy(collId, msg.sender);

        if (!healthy) {
            revert DSCEngine__HealthFactorBelowThreshold(hf);
        }

        // then transfer the coll to user
        removeCollateral(collId, collAmount);
    }

    function _burnDSC(
        bytes32 collId,
        uint256 DSCAmount,
        address burnOnBehalfOf,
        address burnFrom
    ) private {
        // Before burning, fees needs to be collected since the last vault update time
        // to now
        settleProtocolFees(collId, burnOnBehalfOf, DSCAmount);
        // reduce their debt
        shrinkVaultDebt(collId, burnOnBehalfOf, DSCAmount);

        // transfer dsc back to the engine.
        bool success = i_DSC.transferFrom(burnFrom, address(this), DSCAmount);

        if (!success) {
            revert DSCEngine__BurningDSCFailed();
        }

        /// Now DSCEngine contract burns the DSC tokens.
        i_DSC.burn(DSCAmount);
    }

    function settleProtocolFees(
        bytes32 collId,
        address owner,
        uint256 debt
    ) internal {
        // time to charge fee for
        uint256 deltaTime = block.timestamp -
            s_vaults[collId][owner].lastUpdatedAt;

        uint256 accumulatedFees = calculateProtocolFee(debt, deltaTime);

        // Equivalence of these fees in collateral form
        uint256 feeTokenAmount = getTokenAmountFromUsdValue2(
            collId,
            accumulatedFees
        );

        // collateral being charged is already in the engine. Its just a matter of
        // updating the balances treasury appropriately
        // The fee is charged from the vault's locked collateral and not the global
        // balance of the user for that collateral. This is to avoid loss because someone can
        // decide to keep their vault healthy but have zero balance on the global balances.
        // But charging the locked collateral forces the user to pay fees and not evade fees since
        // paying fees has the impact to their health factor which they will make sure to maintain
        // to avoid liquidation.
        // HF is not checked here because sometimes fee could be charged during closure which means no need
        // to enforce HF. So the calling function needs to checkt he HF

        // decrement locked collateral by the fee.
        s_vaults[collId][owner].lockedCollateral -= feeTokenAmount;

        // Increment the fees collected by the same amount.
        s_totalCollectedFeesPerCollateral[collId] += feeTokenAmount;

        // After paying fees, update the timestamp to now so that future payments will begin from
        // now
        // might actually not need it since shrinkVault updates too
        s_vaults[collId][owner].lastUpdatedAt = block.timestamp;
    }

    function settleLiquidationPenalty(
        bytes32 collId,
        address owner,
        uint256 debt
    ) internal {
        uint256 penalty = calculateLiquidationPenalty(debt);

        uint256 penaltyTokenAmount = getTokenAmountFromUsdValue2(
            collId,
            penalty
        );

        s_vaults[collId][owner].lockedCollateral -= penaltyTokenAmount;

        s_totalLiquidationPenaltyPerCollateral[collId] += penaltyTokenAmount;
    }

    /*//////////////////////////////////////////////////////////////
                       COLLATERAL CONFIGURATIONS
    //////////////////////////////////////////////////////////////*/
    // liquidation threshold percentage is the value from
    // Threshold = (Liquidation precision * 100) / Desired Overcollateralization Ratio (%)
    // Check Deepseek cchat here: https://chat.deepseek.com/a/chat/s/767f8d14-e4e1-4e89-b313-690da60cefa2

    function configureCollateral(
        bytes32 collateralId,
        address tokenAddr,
        uint256 interestFee,
        uint256 liquidationThresholdPercentage,
        uint256 minDebtAllowed,
        uint256 liquidationRatio,
        address priceFeed,
        uint8 tknDecimals
    ) external onlyOwner {
        // Only configure supported collateral if not previously set
        if (s_collaterals[collateralId].tokenAddr != address(0)) {
            revert DSCEngine__CollateralConfigurationAlreadySet(collateralId);
        }
        s_collateralIds.push(collateralId);
        s_collaterals[collateralId].tokenAddr = tokenAddr;
        s_collaterals[collateralId].interestFee = interestFee;
        s_collaterals[collateralId]
            .liquidationThresholdPercentage = liquidationThresholdPercentage;
        s_collaterals[collateralId].minDebtAllowed = minDebtAllowed;
        s_collaterals[collateralId].liquidationRatio = liquidationRatio;
        s_collaterals[collateralId].priceFeedAddr = priceFeed;

        s_tokenDecimals[collateralId] = tknDecimals; // should it be removed also at below??
    }

    function removeCollateralConfiguration(
        bytes32 collateralId
    ) external onlyOwner {
        uint256 outstandingDebt = s_collaterals[collateralId]
            .totalNormalizedDebt;
        if (outstandingDebt > 0) {
            revert DSCEngine__CollateralConfigurationCannotBeRemovedWithOutstandingDebt(
                outstandingDebt
            );
        }

        delete s_collaterals[collateralId];

        // Gas intensive removal from array of collateral Ids
        for (uint256 k = 0; k < s_collateralIds.length; k++) {
            if (s_collateralIds[k] == collateralId) {
                s_collateralIds[k] = bytes32(s_collateralIds.length - 1);
                s_collateralIds.pop();
                break;
            }
        }
    }

    function getCollateralSettings(
        bytes32 collateralId
    ) external view returns (Structs.CollateralConfig memory) {
        return s_collaterals[collateralId];
    }

    function getAllowedCollateralIds()
        external
        view
        returns (bytes32[] memory)
    {
        return s_collateralIds;
    }

    function getCollateralAddress(
        bytes32 collId
    ) external view returns (address) {
        return s_collaterals[collId].tokenAddr;
    }

    function getVaultInformation(
        bytes32 collId,
        address owner
    ) external view returns (uint256 collAmount, uint256 dscDebt) {
        collAmount = s_vaults[collId][owner].lockedCollateral;
        dscDebt = s_vaults[collId][owner].dscDebt;

        return (collAmount, dscDebt);
    }
}
