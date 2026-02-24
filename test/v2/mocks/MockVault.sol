// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockVault {
    IERC20 public token;

    constructor(address token_) {
        token = IERC20(token_);
    }

    function depositFrom(
        address from,
        address token_,
        uint256 amount
    ) external {
        bool success = IERC20(token_).transferFrom(from, address(this), amount);
        require(success);
    }

    function release(address token_, address to, uint256 amount) external {
        bool success = IERC20(token_).transfer(to, amount);
        require(success);
    }

    function releaseOnClose(
        address token_,
        address to,
        uint256 amount
    ) external {
        bool success = IERC20(token_).transfer(to, amount);
        require(success);
    }
}
