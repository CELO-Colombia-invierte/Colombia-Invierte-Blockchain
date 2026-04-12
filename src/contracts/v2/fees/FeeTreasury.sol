// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC20, SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

/**
 * @title FeeTreasury
 * @notice Secure vault for protocol fees.
 * @dev Minimal, non-upgradeable, ownable treasury.
 * @author Key Lab Technical Team.
 */
contract FeeTreasury is Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;

  /*//////////////////////////////////////////////////////////////
                               ERRORS
  //////////////////////////////////////////////////////////////*/

  error ZeroAddress();
  error ZeroAmount();
  error InsufficientBalance();
  error TransferFailed();

  /*//////////////////////////////////////////////////////////////
                               EVENTS
  //////////////////////////////////////////////////////////////*/

  event Withdrawn(address indexed token, address indexed to, uint256 amount);
  event NativeWithdrawn(address indexed to, uint256 amount);

  /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(address initialOwner) Ownable(initialOwner) {
    if (initialOwner == address(0)) revert ZeroAddress();
  }

  /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Withdraws accumulated ERC20 tokens from fees.
   * @dev Reverts on zero address/amount or insufficient balance.
   */
  function withdraw(address token, address to, uint256 amount) external onlyOwner nonReentrant {
    if (token == address(0)) revert ZeroAddress();
    if (to == address(0)) revert ZeroAddress();
    if (amount == 0) revert ZeroAmount();
    if (amount > IERC20(token).balanceOf(address(this))) {
      revert InsufficientBalance();
    }

    IERC20(token).safeTransfer(to, amount);
    emit Withdrawn(token, to, amount);
  }

  /**
   * @notice Withdraws native Ether from the contract.
   * @dev NonReentrant protects against reentrancy via .call.
   */
  function withdrawNative(address payable to, uint256 amount) external onlyOwner nonReentrant {
    if (to == address(0)) revert ZeroAddress();
    if (amount == 0) revert ZeroAmount();
    if (amount > address(this).balance) revert InsufficientBalance();

    (bool success,) = to.call{value: amount}('');
    if (!success) revert TransferFailed();

    emit NativeWithdrawn(to, amount);
  }

  receive() external payable {}
}
