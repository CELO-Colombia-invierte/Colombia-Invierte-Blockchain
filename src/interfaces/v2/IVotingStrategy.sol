// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IVotingStrategy
 * @notice Interface for defining custom voting strategies for governance modules.
 * @author Key Lab Technical Team.
 */
interface IVotingStrategy {
  error ZeroAddress();

  function getVotingPower(address user, uint256 snapshotBlock) external view returns (uint256);
}
