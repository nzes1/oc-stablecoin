// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/ERC20.sol";

contract ERC20Like is ERC20 {
    uint8 private immutable i_customDecimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        i_customDecimals = decimals_;
    }

    // ovverride the decimals function
    function decimals() public view override returns (uint8) {
        return i_customDecimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}
