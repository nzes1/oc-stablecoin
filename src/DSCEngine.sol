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

/**
 * @title DSCEngine
 * @author @nzesi_eth
 * @notice The DSCEngine contract is the engine contract for the Decentralized Stable Coin (DSC) system.
 * @dev The DSCEngine contract is responsible for managing the collateral deposits, DSC minting,
 * DSC burning, collateral redemption, and liquidation of accounts that become undercollateralized.
 * @dev For a user to be above the liquidation threshold, they have to maintain an overcollateralization
 * of 200%.
 */
contract DSCEngine is
    Storage,
    Ownable,
    ReentrancyGuard,
    CollateralManager,
    VaultManager
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
     * @dev Precision factors to maintain the precision of the calculations of prices in USD.
     */
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private constant ADDITIONAL_PRECISION_FACTOR = 1e10;

    /**
     * @dev The liquidation threshold (percentage) for the health factor.
     * @dev The user always has to have 200% overcollateralization.
     */
    uint256 private constant LIQUIDATION_THRESHOLD = 50;

    /**
     * @dev The precision factor for the liquidation threshold.
     */
    // uint256 private constant LIQUIDATION_PRECISION = 100;

    /**
     * @dev The liquidator 10% bonus for liquidating an account.
     */
    uint256 private constant LIQUIDATOR_BONUS = 10;

    /**
     * @dev The minimum health factor allowed scaled by 1e18 since
     * the health factor is scaled up by 1e18 also.
     */
    // uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    /**
     * @dev The address of the DSC token
     */
    DecentralizedStableCoin private immutable i_DSC;

    /**
     * error DSCEngine__MintingDSCFailed();
     * @dev The list of addresses of the permitted collateral tokens.
     * @dev The list is set in the constructor.
     */
    address[] private s_collateralTokens;

    /**
     * @dev The chainlink price feeds addresses for the collateral tokens.
     */
    mapping(address collateralTkn => address tknPriceFeed) private s_priceFeeds;

    /**
     * @dev User's collateral deposits per collateral token.
     */
    mapping(address account => mapping(address token => uint256 amount))
        private s_collateralDeposits;

    /**
     * @dev The amount of DSC minted per user.
     */
    mapping(address account => uint256 DSCBalance) private s_DSCMinted;

    /**
     * @dev Store vaults by collateral type and owner of the vault.
     */

    /**
     * @dev Total DSC supply in circulation
     */
    uint256 private s_totalDSCDebt;

    /**
     * @dev Freeze system flag.
     */
    bool private live;
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(
        address indexed depositor,
        address indexed token,
        uint256 amount
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed recipient,
        address indexed token,
        uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__CollateralTokensAddressesAndPriceFeedsAddressesLengthMismatch();
    error DSCEngine__CollateralTokenNotAllowed();
    error DSCEngine__CollateralTransferFailed();
    error DSCEngine__MintingDSCFailed();
    error DSCEngine__BurningDSCFailed();
    error DSCEngine__RedeemingCollateralFailed();
    error DSCEngine__HealthFactorBelowThreshold(uint256 healthFactor);
    error DSCEngine__HealthFactorNotLiquidatable(uint256 healthFactor);
    error DSCEngine__LiquidationHasNotImprovedHealthFactor();
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

    /**
     * @notice Modifier to check that the token is allowed as collateral.
     * @dev Reverts if the token is not allowed.
     */
    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__CollateralTokenNotAllowed();
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
        if (tokenAddresses.length != priceFeedsAddresses.length) {
            revert DSCEngine__CollateralTokensAddressesAndPriceFeedsAddressesLengthMismatch();
        }

        for (uint256 k = 0; k < tokenAddresses.length; k++) {
            s_priceFeeds[tokenAddresses[k]] = priceFeedsAddresses[k];
            s_collateralTokens.push(tokenAddresses[k]);
        }

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

    /**
     * @notice The function allows users to redeem collateral tokens and burn DSC tokens in
     * a single transaction.
     * @dev The user has to burn the DSC tokens before redeeming the collateral tokens.
     * @param tokenAddr The address of the collateral token.
     * @param collateralAmount The amount of collateral tokens to redeem.
     * @param DSCAmountToBurn The amount of DSC tokens to burn.
     */
    function redeemCollateralForDSC(
        address tokenAddr,
        uint256 collateralAmount,
        uint256 DSCAmountToBurn
    ) external {
        // Burn the DSC before redeeming the collateral.
        burnDSC(DSCAmountToBurn);
        redeemCollateral(tokenAddr, collateralAmount);

        // No need to check health factor here as it is checked in the `redeemCollateral()`
        /// and the `burnDSC` functions.
    }

    /**
     * @notice The function allows users to liquidate an account that has a health factor below
     * the minimum health factor allowed.
     * @notice It is assumed that the system has a 200% overcollateralization ratio.
     * @param token The collateral token where the user's position is below the liquidation threshold.
     * @param account The user account to be liquidated.
     * @param DSCDebtToCover The amount of DSC that the user whose position is below the liquidation
     * threshold owes to the DSC system/has. This is the amount that the liquidator has to cover by
     * burning DSC tokens in order to receive the collateral tokens belonging to the user.
     */
    function liquidateAccount(
        address token,
        address account,
        uint256 DSCDebtToCover
    ) external moreThanZero(DSCDebtToCover) nonReentrant {
        /// Get health factor before liquidating the account.
        uint256 startingHealthFactorOfAccount = _healthFactor(account);

        if (startingHealthFactorOfAccount >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorNotLiquidatable(
                startingHealthFactorOfAccount
            );
        }

        /// Get the collateral tokens amount the liquidator gets or redeems from
        /// the DSC debt to cover. i.e., the liquidator gets the collateral tokens for burning
        /// their DSC tokens on behalf of an undercollateralized account.
        uint256 collateralAmountFromDebtCovered = getTokenAmountFromUSDValue(
            token,
            DSCDebtToCover
        );

        /// The bonus the liquidator gets on top of the collateral for liquidating an account.
        uint256 bonusCollateral = (collateralAmountFromDebtCovered *
            LIQUIDATOR_BONUS) / LIQUIDATION_PRECISION;

        /// Total collateral the liquidator gets from liquidating an account.
        uint256 totalCollateralExpected = collateralAmountFromDebtCovered +
            bonusCollateral;

        /// Sending the collateral tokens to the liquidator.
        /**
         * @audit Identified that Liquidation fails when the liquidatable account has an
         * overcollateralization of 100% - 110%.
         * The total collateral that the liquidatable account needs to have in order for liquidation
         * to be successful is calculated as below:
         * Total Collateral Required = Collateral Redeemed+Bonus Collateral
         * Total Collateral Required = (DSCDebtToCover / Price of Collateral Token in USD) +
         * ((DSCDebtToCover / Price of Collateral Token in USD) * (LIQUIDATOR_BONUS / LIQUIDATION_PRECISION))
         * @
         */
        (bool liquidatable, uint256 bonusAvailable) = _checkCollateral(
            token,
            totalCollateralExpected,
            collateralAmountFromDebtCovered,
            account
        );

        uint256 totalCollateralToGet;
        if (!liquidatable) {
            revert DSCEngine__AccountNotLiquidatable();
        } else {
            totalCollateralToGet =
                collateralAmountFromDebtCovered +
                bonusAvailable;
        }

        _redeemCollateral(token, totalCollateralToGet, account, msg.sender);

        /// Now burning the DSC tokens from the liquidator's account on behalf of the account
        /// which is being liquidated.
        _burnDSC(DSCDebtToCover, account, msg.sender);

        /// Make sure liquidation has improved the health factor of the account.
        uint256 endingHealthFactorOfAccount = _healthFactor(account);
        if (endingHealthFactorOfAccount <= startingHealthFactorOfAccount) {
            revert DSCEngine__LiquidationHasNotImprovedHealthFactor();
        }

        /// Additionally, after liquidating an account, the liquidator's health factor has also
        /// to be maintained - this process should not affect the liquidator's health factor. Revert
        /// otherwise
        _revertIfHealthFactorIsBelowThreshold(msg.sender);
    }

    /**
     * @dev Get an account's collateral balance of a particular token.
     */
    function getAccountCollateral(
        address token,
        address account
    ) external view returns (uint256 balance) {
        return s_collateralDeposits[account][token];
    }

    /**
     *
     * @param account The address to fetch metadata info for.
     * @return DSCBal The address's DSC balance
     * @return totalCollateralValueInUsd The USD value of the total collateral for that address.
     */
    function getAccountInformation(
        address account
    )
        external
        view
        returns (uint256 DSCBal, uint256 totalCollateralValueInUsd)
    {
        (DSCBal, totalCollateralValueInUsd) = _getAccountInfo(account);
    }

    // /**
    //  * @notice The function allows users to deposit collateral tokens.
    //  * @dev The user has to approve the transfer of the collateral tokens to this contract
    //  * prior to initiating the deposit.
    //  * @dev The amount the user deposits has to be more than zero. The token also has to be
    //  * allowed as collateral. The function reverts otherwise.
    //  * @param tokenAddr The address of the collateral token.
    //  * @param amount The amount of collateral tokens to deposit.
    //  */
    // function depositCollateral(
    //     address tokenAddr,
    //     uint256 amount
    // ) public moreThanZero(amount) isAllowedToken(tokenAddr) nonReentrant {
    //     s_collateralDeposits[msg.sender][tokenAddr] += amount;

    //     emit CollateralDeposited(msg.sender, tokenAddr, amount);

    //     bool success = IERC20(tokenAddr).transferFrom(
    //         msg.sender,
    //         address(this),
    //         amount
    //     );

    //     if (!success) {
    //         revert DSCEngine__CollateralTransferFailed();
    //     }
    // }

    function depositCollateral(
        bytes32 collId,
        uint256 amount
    ) public nonReentrant {
        addCollateral(collId, amount);
    }

    // need inheritance to avoid change of msg.sender
    function depositEtherCollateralAndMintDSC(
        uint256 DSCAmount
    ) external payable {
        addEtherCollateral();
        mintDSC("ETH", msg.value, DSCAmount);
    }

    // /**
    //  * @notice The function mints DSC tokens to a user after depositing collateral.
    //  * @dev The function calls the `mint()` function of the DecentralizedStableCoin
    //  * token contract to mint the DSC tokens. Only the DSCEngine contract can mint DSC tokens.
    //  * @dev The user has to have a health factor greater than the minimum health factor
    //  * allowed. The function reverts otherwise.
    //  * @param DSCAmountToMint The amount of DSC tokens to mint.
    //  */
    // function mintDSC(
    //     uint256 DSCAmountToMint
    // ) public moreThanZero(DSCAmountToMint) nonReentrant {
    //     s_DSCMinted[msg.sender] += DSCAmountToMint;
    //     _revertIfHealthFactorIsBelowThreshold(msg.sender);

    //     bool mintStatus = i_DSC.mint(msg.sender, DSCAmountToMint);

    //     if (!mintStatus) {
    //         revert DSCEngine__MintingDSCFailed();
    //     }
    // }

    function mintDSC(
        bytes32 collId,
        uint256 collAmount,
        uint256 DSCAmount
    ) public moreThanZero(DSCAmount) nonReentrant {
        // need coll for that vault
        // need balance for the coll which is 150% value of mint amount.
        // update+ vault
        // send dsc to user

        // increase their debt first
        createVault(collId, collAmount, DSCAmount);

        // Vault has to be overcollateralized as per the set configs for that collateral
        (bool healthy, uint256 healthFactor) = isVaultHealthy(
            collId,
            msg.sender
        );

        if (!healthy) {
            revert DSCEngine__HealthFactorBelowThreshold(healthFactor);
        }

        // Mint DSC to user address
        bool mintStatus = i_DSC.mint(msg.sender, DSCAmount);

        if (!mintStatus) {
            revert DSCEngine__MintingDSCFailed();
        }
    }

    /**
     * @notice The function allows users to redeem/retrieve their collateral tokens.
     * @param tokenAddr The collateral token address to redeem.
     * @param amount The amount of collateral to redeem.
     */
    function redeemCollateral(
        address tokenAddr,
        uint256 amount
    ) public moreThanZero(amount) nonReentrant {
        _redeemCollateral(tokenAddr, amount, msg.sender, msg.sender);
        // Health factor has to be above the threshold after redeeming collateral.
        _revertIfHealthFactorIsBelowThreshold(msg.sender);
    }

    /**
     * @notice The function allows users to burn DSC tokens.
     * @dev The function calls the `burn()` function of the DecentralizedStableCoin
     * token contract to burn the DSC tokens. Only the DSCEngine contract can burn DSC tokens.
     * @param amount The amount of DSC tokens to burn.
     */
    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);

        // Need to check if this will ever hit.
        _revertIfHealthFactorIsBelowThreshold(msg.sender);
    }

    /**
     * @notice Calculates the total collateral value in USD for a user.
     * @dev The function loops through the collateral tokens array and aggregates the total
     * collateral value in USD for the user per collateral token.
     * @param account The address of the account to get the collateral value in USD.
     * @return totalValueInUSD The total collateral value in USD for the user.
     */
    function getAccountCollateralValueInUSD(
        address account
    ) public view returns (uint256 totalValueInUSD) {
        uint256 totalCollateralValueInUSD;
        /// Loop through the collateral tokens and use that to get user's
        /// total collateral amount. Then pass this amount to `getValueInUSD()` to get
        /// the USD value equivalent.
        for (uint256 k = 0; k < s_collateralTokens.length; k++) {
            address tokenAddr = s_collateralTokens[k];
            uint256 tokenAmount = s_collateralDeposits[account][tokenAddr];
            totalCollateralValueInUSD += getValueInUSD(tokenAddr, tokenAmount);
        }
        return totalCollateralValueInUSD;
    }

    /**
     * @notice Calculates the value of the token amount given in USD.
     * @dev The function uses the Chainlink price feed to get the price of the token in USD.
     * @param token The address of the token to get the value in USD.
     * @param amount The amount of the token to get the value in USD.
     * @return valueInUSD The value of the token amount in USD with 18 decimals.
     */
    function getValueInUSD(
        address token,
        uint256 amount
    ) public view returns (uint256 valueInUSD) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 priceInUsd, , , ) = priceFeed.latestRoundDataStalenessCheck();

        /// Type casting the price and making sure precision is maintained.
        return (((uint256(priceInUsd) * ADDITIONAL_PRECISION_FACTOR) * amount) /
            PRECISION_FACTOR);
    }

    /**
     * @notice The function gets the collateral token amount from the USD value.
     * @dev The function uses the Chainlink price feed to get the price of the token in USD.
     * @param token The address of the token to get the collateral token amount.
     * @param usdAmountInWei The USD value in wei(18 decimals) to get the collateral token amount.
     * @return tokenAmount The token amount from the USD value given.
     */
    function getTokenAmountFromUSDValue(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256 tokenAmount) {
        /// Get price feed for the token
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 priceInUsd, , , ) = priceFeed.latestRoundDataStalenessCheck();

        /// Calculate the token amount from the USD value
        /// e.g., 1 ether token = $2000
        ///  == 1e18 = $2000
        /// ==  ??   =   $30
        /// cross multiply to get the token amount
        /// ($30 * 1e18 ) / $2000
        tokenAmount =
            (usdAmountInWei * PRECISION_FACTOR) /
            (uint256(priceInUsd) * ADDITIONAL_PRECISION_FACTOR);

        return tokenAmount;
    }

    /**
     * @notice TPublic function to get the health factor for a user.
     * @param account The address of the account to get the health factor.
     * @return healthFactor The health factor for the `account`.
     */
    function getHealthFactor(
        address account
    ) public view returns (uint256 healthFactor) {
        return _healthFactor(account);
    }

    /**
     * @notice The function gets the collateral tokens allowed as collateral.
     * @return collateralTokens The list of addresses of the collateral tokens.
     */
    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    /**
     * @notice The user has to always have a health factor greater than the minimum health factor.
     * @dev Health factor is only checked when the user has DSC balance of more than zero.
     * @dev The function reverts if the health factor is below the minimum health factor allowed.
     * @param account The address of the account to check the health factor.
     */
    function _revertIfHealthFactorIsBelowThreshold(
        address account
    ) internal view {
        if (s_DSCMinted[account] > 0) {
            uint256 accountHealthFactor = _healthFactor(account);

            if (accountHealthFactor < MIN_HEALTH_FACTOR) {
                revert DSCEngine__HealthFactorBelowThreshold(
                    accountHealthFactor
                );
            }
        }
    }

    /**
     * @notice The function calculates the health factor for a user.
     * @dev The health factor is the ratio of the total collateral value in USD to the
     * total DSC minted.
     * @dev The user always has to have 200% overcollateralization.
     * @param account The address of the account to get the health factor.
     * @return healthFactor The health factor for the user.
     */
    function _healthFactor(
        address account
    ) private view returns (uint256 healthFactor) {
        (
            uint256 totalDSCMinted,
            uint256 totalCollateralValueInUSD
        ) = _getAccountInfo(account);

        /// Only 50% of the collateral value is considered safe for protecting against liquidation.
        /// i.e., the user has to always have a balance of 2x worth of collateral to their total
        /// DSC minted - otherwise, the health factor is below 1 and they get liquidated.
        /// User has to have some DSC minted to calculate the health factor.
        if (totalDSCMinted > 0) {
            uint256 adjustedCollateralForThreshold = (totalCollateralValueInUSD *
                    LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

            /// A precision of 1e18 (`PRECISION_FACTOR`) is maintained before division to avoid precision loss.
            healthFactor =
                (adjustedCollateralForThreshold * PRECISION_FACTOR) /
                totalDSCMinted;

            return healthFactor;
        }
    }

    /**
     * @notice The function gets the account information for a user.
     * @dev The function returns the total DSC minted and the total collateral value in USD.
     * @param account The address of the account to get the information.
     * @return userDSCMinted The total DSC minted for the user.
     * @return collateralValueInUSD The total collateral value in USD for the user.
     */
    function _getAccountInfo(
        address account
    )
        private
        view
        returns (uint256 userDSCMinted, uint256 collateralValueInUSD)
    {
        userDSCMinted = s_DSCMinted[account];
        collateralValueInUSD = getAccountCollateralValueInUSD(account);
    }

    /**
     * @notice The internal function to redeem collateral tokens.
     * @param tokenAddr The address of the collateral token.
     * @param amount The amount of collateral tokens to redeem.
     * @param from The address to redeem the collateral tokens from.
     * @param to The address to send the collateral tokens to.
     */
    function _redeemCollateral(
        address tokenAddr,
        uint256 amount,
        address from,
        address to
    ) private {
        s_collateralDeposits[from][tokenAddr] -= amount;

        emit CollateralRedeemed(from, to, tokenAddr, amount);

        bool success = IERC20(tokenAddr).transfer(to, amount);
        if (!success) {
            revert DSCEngine__RedeemingCollateralFailed();
        }
    }

    /**
     * @notice The internal function to burn DSC tokens.
     * @dev This low-level function does not check the health factor. The calling function
     * has to check the health factor after calling this function and revert if the health factor
     *
     * @param DSCAmountToBurn The amount of DSC tokens to burn.
     * @param burnOnBehalfOf The address to burn the DSC tokens on behalf of.
     * @param burnDSCFrom The address to burn the DSC tokens from.
     */
    function _burnDSC(
        uint256 DSCAmountToBurn,
        address burnOnBehalfOf,
        address burnDSCFrom
    ) private {
        /// Incase of liquidation, the liquidators burn DSC Amount gets deducted
        /// from the user who's being liquidated so that they may not claim the DSC after liquidation.
        s_DSCMinted[burnOnBehalfOf] -= DSCAmountToBurn;

        /// Transfer the DSC from the user (or liquidator incase of a liquidation flow)
        /// to the DSCEngine contract before burning.
        bool success = i_DSC.transferFrom(
            burnDSCFrom,
            address(this),
            DSCAmountToBurn
        );

        if (!success) {
            revert DSCEngine__BurningDSCFailed();
        }

        /// Now DSCEngine contract burns the DSC tokens.
        i_DSC.burn(DSCAmountToBurn);
    }

    function _burnDSC2(
        bytes32 collId,
        uint256 collAmount,
        uint256 DSCAmount,
        address burnOnBehalfOf,
        address burnFrom
    ) private {
        // reduce their debt
        shrinkVault(collId, burnOnBehalfOf, collAmount, DSCAmount);

        // transfer dsc back to the engine.
        bool success = i_DSC.transferFrom(burnFrom, address(this), DSCAmount);

        if (!success) {
            revert DSCEngine__BurningDSCFailed();
        }

        /// Now DSCEngine contract burns the DSC tokens.
        i_DSC.burn(DSCAmount);
    }

    /**
     *
     * @param tokenAddr The collateral token whose balance is being checked.
     * @param totalRequiredCollateral The total collateral required for liquidation including bonus.
     * @param collateralWithoutBonus The total collateral required for liquidation without bonus.
     * @param account The account which is being liquidated.
     * @return liquidatable A boolean indicating if the account is liquidatable with the current balance.
     * @return bonus The maximum bonus available for liquidating the account.
     */
    function _checkCollateral(
        address tokenAddr,
        uint256 totalRequiredCollateral,
        uint256 collateralWithoutBonus,
        address account
    ) private view returns (bool liquidatable, uint256 bonus) {
        uint256 collateral = s_collateralDeposits[account][tokenAddr];
        if (collateral < totalRequiredCollateral) {
            if (collateral < collateralWithoutBonus) {
                return (false, 0);
            } else if (collateral >= collateralWithoutBonus) {
                return (true, (collateral - collateralWithoutBonus));
            }
        } else {
            return (true, (totalRequiredCollateral - collateralWithoutBonus));
        }
    }

    /*//////////////////////////////////////////////////////////////
                       COLLATERAL CONFIGURATIONS
    //////////////////////////////////////////////////////////////*/
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
}
