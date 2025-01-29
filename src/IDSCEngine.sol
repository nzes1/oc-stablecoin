// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

interface IDSCEngine {
    /**
     * @dev Deposit collateral to mint DSC tokens
     * @param tokenAddr Address of the collateral token
     * @param amount Amount of collateral to deposit
     * @param DSCAmount Amount of DSC tokens to mint
     */
    function depositCollateralAndMintDSC(address tokenAddr, uint256 amount, uint256 DSCAmount) external;

    /**
     * @dev Deposit collateral to mint DSC tokens
     * @param tokenAddr Address of the collateral token
     * @param amount Amount of collateral to deposit
     */
    function depositCollateral(address tokenAddr, uint256 amount) external;

    /**
     * @dev Redeem collateral for DSC tokens
     * @param tokenAddr Address of the collateral token
     * @param amount Amount of collateral to redeem
     * @param DSCAmount Amount of DSC tokens to burn
     */
    function redeemCollateralForDSC(address tokenAddr, uint256 amount, uint256 DSCAmount) external;

    /**
     * @dev Redeem collateral from the system.
     * @param amount Amount of collateral to redeem/withdraw.
     */
    function redeemCollateral(address tokenAddr, uint256 amount) external;

    /**
     * @dev Mint DSC tokens
     * @param amount Amount of DSC tokens to mint
     */
    function mintDSC(uint256 amount) external;

    /**
     * @dev Burn DSC tokens
     * @param amount Amount of DSC tokens to burn
     */
    function burnDSC(uint256 amount) external;

    /**
     * @dev Liquidate account
     * @param tokenAddr Address of the collateral token
     * @param account Address of the account to liquidate
     * @param DSCToBurn Amount of liquidator DSC tokens to burn
     */
    function liquidateAccount(address tokenAddr, address account, uint256 DSCToBurn) external;

    /**
     * @dev Get the health factor of an account
     * @return Health factor of the account
     */
    function getHealthFactor(address account) external returns (uint256);
}
