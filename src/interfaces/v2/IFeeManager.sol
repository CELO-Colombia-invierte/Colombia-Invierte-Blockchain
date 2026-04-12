// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IFeeManager
 * @notice Interface for managing module fees and treasury.
 * @author Key Lab Technical Team.
 */
interface IFeeManager {
  /*//////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  error ZeroAddress();
  error FeeTooHigh();
  error FeeNotConfigured();

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  event FeeUpdated(bytes32 indexed feeType, uint16 newBps);
  event TreasuryUpdated(address indexed newTreasury);

  /*//////////////////////////////////////////////////////////////
                              CORE
  //////////////////////////////////////////////////////////////*/

  function initialize(address treasury_) external;

  function setFee(bytes32 feeType, uint16 bps) external;

  function setTreasury(address newTreasury) external;

  function calculateFee(bytes32 feeType, uint256 amount) external view returns (uint256 feeAmount, uint256 netAmount);

  function feeTreasury() external view returns (address);
}
