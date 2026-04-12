// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IStakeholder
 * @notice Interface for checking stakeholder status in a project.
 * @author Key Lab Technical Team.
 */
interface IStakeholder {
  function isStakeholder(address user) external view returns (bool);
}
