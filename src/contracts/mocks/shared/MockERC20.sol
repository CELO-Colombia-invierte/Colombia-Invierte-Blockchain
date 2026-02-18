// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @notice Minimal ERC20 token for testing purposes with unrestricted minting.
 */
contract MockERC20 is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}

    /// @notice Mints `amount` tokens to `to`. No access control by design.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
