// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IERC20 as ERC20Like} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";
import {Structs} from "./Structs.sol";
import {Storage} from "./Storage.sol";

/**
 * @title CollateralManager
 * @author Nzesi
 * @notice Collateral deposit and withdrawal management for the DSCEngine.
 * @dev Functions to deposit and withdraw ether and ERC20 tokens as collateral.
 * @dev The contract uses a mapping to track the collateral balances of each user.
 */
contract CollateralManager is Storage {

    /// Errors
    error CM__CollateralTokenNotApproved();
    error CM__ZeroAmountNotAllowed();
    error CM__AmountExceedsCurrentBalance(bytes32 collId, uint256 bal);

    /// Events
    event CM__CollateralDeposited(bytes32 indexed collId, address indexed depositor, uint256 amount);
    event CM__CollateralWithdrawn(bytes32 indexed collId, address indexed user, uint256 amount);

    /**
     * @notice Allows the user to deposit ether as collateral.
     * @dev Deposited ether amount is accessed via msg.value. Function is public and payable
     * to allow users to send ether directly to the DSCEngine contract.
     */
    function addEtherCollateral() public payable {
        address depositor = msg.sender;
        uint256 depositAmount = msg.value;
        if (depositAmount == 0) revert CM__ZeroAmountNotAllowed();
        s_collBalances["ETH"][depositor] += depositAmount;

        emit CM__CollateralDeposited("ETH", depositor, depositAmount);
    }

    /**
     * @notice Allows the user to deposit approved ERC20 tokens as collateral.
     * @dev User must approve the DSCEngine contract to spend the specified
     * amount of tokens before calling this function.
     * @param collId The id of the collateral token.
     * @param collAmt The amount of collateral tokens to deposit.
     */
    function addCollateral(bytes32 collId, uint256 collAmt) internal {
        if (collAmt == 0) revert CM__ZeroAmountNotAllowed();

        // Check if the collateral is allowed and get its token address
        (bool allowed, address collTknAddr) = isAllowed(collId);

        // Cache msg.sender to save gas
        address depositor = msg.sender;

        // Revert if the collateral is not allowed/approved.
        if (!allowed) {
            revert CM__CollateralTokenNotApproved();
        }
        // Perform ERC20 transfer from the depositor to this contract
        else {
            bool success = ERC20Like(collTknAddr).transferFrom(depositor, address(this), collAmt);
            require(success, "Collateral Deposit Failed");
            s_collBalances[collId][depositor] += collAmt;
        }
        // Emit deosit event
        emit CM__CollateralDeposited(collId, depositor, collAmt);
    }

    /**
     * @notice Allows the user to withdraw collateral from the protocol.
     * @dev The user must have enough collateral to withdraw the specified amount.
     * @dev The function checks if the collateral is ether or an ERC20 token and handles
     * the withdrawal accordingly. A withdrawal event is emitted after the transfer.
     * @param collId The id of the collateral token.
     * @param amount The amount of collateral to withdraw.
     */
    function removeCollateral(bytes32 collId, uint256 amount) public {
        // Cache msg.sender to save gas
        address caller = msg.sender;

        if (amount == 0) revert CM__ZeroAmountNotAllowed();
        if (s_collBalances[collId][caller] < amount) {
            revert CM__AmountExceedsCurrentBalance(collId, s_collBalances[collId][caller]);
        }
        s_collBalances[collId][caller] -= amount;

        emit CM__CollateralWithdrawn(collId, caller, amount);

        // Check if the collateral is ether or an ERC20 token
        // If it is ether, send the ether to the caller
        // If it is an ERC20 token, transfer the tokens to the caller
        if (collId == "ETH") {
            (bool success,) = payable(caller).call{value: amount}("");
            require(success, "Ether Transfer Failed");
        } else {
            // Get the address of this collateral
            address addr = s_collaterals[collId].tokenAddr;
            ERC20Like(addr).transfer(caller, amount);
        }
    }

    /**
     * @notice Checks if the collateral is allowed and returns its address.
     * @dev Check if a collateral with the given id is allowed in the protocol.
     * @param collId The id of the collateral token.
     * @return allowed true if the collateral is allowed, false otherwise.
     * @return addr The address of the collateral token.
     */
    function isAllowed(bytes32 collId) private view returns (bool allowed, address addr) {
        Structs.CollateralConfig memory config;
        config = s_collaterals[collId];

        // Check if the collateral is allowed
        if (config.tokenAddr == address(0)) {
            return (false, config.tokenAddr);
        } else {
            return (true, config.tokenAddr);
        }
    }

}
