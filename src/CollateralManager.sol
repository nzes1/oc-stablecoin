// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IERC20 as ERC20Like} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";
import {Structs} from "./Structs.sol";
import {Storage} from "./Storage.sol";

/**
 * @title CollateralManager
 * @author Nzesi
 * @notice Manages collateral deposits and withdrawals for the DSCEngine protocol.
 * @dev Supports handling of both native Ether and ERC20 token collateral.
 * @dev Tracks individual user collateral balances and enforces protocol collateral logic.
 */
contract CollateralManager is Storage {

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CM__CollateralDeposited(bytes32 indexed collId, address indexed depositor, uint256 amount);
    event CM__CollateralWithdrawn(bytes32 indexed collId, address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error CM__CollateralTokenNotApproved();
    error CM__ZeroAmountNotAllowed();
    error CM__AmountExceedsCurrentBalance(bytes32 collId, uint256 bal);

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Deposits Ether into the protocol as collateral for the sender.
     * @dev Accepts Ether via msg.value and updates the sender's collateral balance.
     * @dev The function is payable and public to enable direct Ether transfers.
     */
    function addEtherCollateral() public payable {
        address depositor = msg.sender;
        uint256 depositAmount = msg.value;
        if (depositAmount == 0) revert CM__ZeroAmountNotAllowed();
        s_collBalances["ETH"][depositor] += depositAmount;
        emit CM__CollateralDeposited("ETH", depositor, depositAmount);
    }

    /**
     * @notice Withdraws a specified amount of collateral from the protocol.
     * @dev Requires the user to have sufficient collateral balance. Determines
     * if the collateral is Ether or ERC20 and processes the withdrawal accordingly.
     * @dev Emits a withdrawal event upon successful transfer.
     * @param collId The identifier of the collateral token.
     * @param amount The amount of collateral to withdraw.
     */
    function removeCollateral(bytes32 collId, uint256 amount) public {
        if (amount == 0) revert CM__ZeroAmountNotAllowed();

        address caller = msg.sender;
        if (s_collBalances[collId][caller] < amount) {
            revert CM__AmountExceedsCurrentBalance(collId, s_collBalances[collId][caller]);
        }

        s_collBalances[collId][caller] -= amount;

        emit CM__CollateralWithdrawn(collId, caller, amount);

        if (collId == "ETH") {
            (bool success,) = payable(caller).call{value: amount}("");
            require(success, "Ether Transfer Failed");
        } else {
            address addr = s_collaterals[collId].tokenAddr;
            ERC20Like(addr).transfer(caller, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Deposits approved ERC20 tokens into the protocol as collateral.
     * @dev The user must approve the DSCEngine contract to spend the specified
     * token amount before invoking this function.
     * @param collId The identifier of the ERC20 collateral token.
     * @param collAmt The amount of tokens to be deposited as collateral.
     */
    function addCollateral(bytes32 collId, uint256 collAmt) internal {
        if (collAmt == 0) revert CM__ZeroAmountNotAllowed();

        address depositor = msg.sender;
        (bool allowed, address collTknAddr) = isAllowed(collId);

        if (!allowed) {
            revert CM__CollateralTokenNotApproved();
        } else {
            bool success = ERC20Like(collTknAddr).transferFrom(depositor, address(this), collAmt);
            require(success, "Collateral Deposit Failed");
            s_collBalances[collId][depositor] += collAmt;
        }

        emit CM__CollateralDeposited(collId, depositor, collAmt);
    }

    /*//////////////////////////////////////////////////////////////
                           PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Determines if a collateral token is allowed in the protocol.
     * @dev Looks up the collateral by its ID and verifies its approval status.
     * @param collId The identifier of the collateral token.
     * @return allowed True if the collateral is approved, false otherwise.
     * @return addr The address of the collateral token contract.
     */
    function isAllowed(bytes32 collId) private view returns (bool allowed, address addr) {
        Structs.CollateralConfig memory config = s_collaterals[collId];

        if (config.tokenAddr == address(0)) {
            return (false, config.tokenAddr);
        } else {
            return (true, config.tokenAddr);
        }
    }

}
