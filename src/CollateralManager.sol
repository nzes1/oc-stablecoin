// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IERC20 as ERC20Like} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";
import {Structs} from "./Structs.sol";
import {Storage} from "./Storage.sol";

// A way to deposit any ERC20 compliant token
// A way to deposit non-erc20 tokens especially the native tokens such as
// ETH, BTC, Polkadot etc
// A way to remove the tokens.
// Storage of the state of balances

contract CollateralManager is Storage {

    error CM__CollateralTokenNotApproved();
    error CM__ZeroAmountNotAllowed();
    error CM__AmountExceedsCurrentBalance(bytes32 collId, uint256 bal);

    event CM__CollateralDeposited(bytes32 indexed collId, address indexed depositor, uint256 amount);

    event CM__CollateralWithdrawn(bytes32 indexed collId, address indexed user, uint256 amount);

    function addEtherCollateral() public payable {
        // cache ether deposit amount and depositor
        address depositor = msg.sender;
        uint256 depositAmount = msg.value;
        if (depositAmount == 0) revert CM__ZeroAmountNotAllowed();
        s_collBalances["ETH"][depositor] += depositAmount;

        emit CM__CollateralDeposited("ETH", depositor, depositAmount);
    }

    // Confirm if zero amount transfers are checked on the ERC20 contract side.-- found out that its
    // not checked. Write tests for that confirmation before implementing the check here.
    // User has to pre-approve DSCEngine contract prior to calling this function.
    function addCollateral(bytes32 collId, uint256 collAmt) internal {
        if (collAmt == 0) revert CM__ZeroAmountNotAllowed();
        // Check collateral is allowed and get the address
        (bool allowed, address collTknAddr) = isAllowed(collId);

        // Save gas by caching msg.sender
        address depositor = msg.sender;

        // Has to be permitted
        if (!allowed) {
            revert CM__CollateralTokenNotApproved();
        }
        // ERC20 transfers
        else {
            bool success = ERC20Like(collTknAddr).transferFrom(depositor, address(this), collAmt);
            require(success, "Collateral Deposit Failed");
            s_collBalances[collId][depositor] += collAmt;
        }
        emit CM__CollateralDeposited(collId, depositor, collAmt);
    }

    function removeCollateral(bytes32 collId, uint256 amount) public {
        // CEI
        // Ether removal
        // They need to have enough to remove

        //cache msg.sender
        address caller = msg.sender;
        if (amount == 0) revert CM__ZeroAmountNotAllowed();
        if (s_collBalances[collId][caller] < amount) {
            revert CM__AmountExceedsCurrentBalance(collId, s_collBalances[collId][caller]);
        }
        s_collBalances[collId][caller] -= amount;

        emit CM__CollateralWithdrawn(collId, caller, amount);

        // Ether withdrawal
        if (collId == "ETH") {
            (bool success,) = payable(caller).call{value: amount}("");
            require(success, "Ether Transfer Failed");
        } else {
            // Get the address of this collateral
            address addr = s_collaterals[collId].tokenAddr;
            ERC20Like(addr).transfer(caller, amount);
        }
    }

    function isAllowed(bytes32 collId) private view returns (bool allowed, address addr) {
        Structs.CollateralConfig memory config;
        config = s_collaterals[collId];
        //check collateral settings have been authorized by governance.
        if (config.tokenAddr == address(0)) {
            return (false, config.tokenAddr);
        } else {
            return (true, config.tokenAddr);
        }
    }

}
