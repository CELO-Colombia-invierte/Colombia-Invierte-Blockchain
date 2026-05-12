// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IMilestonesModule
 * @notice Interface for the milestones module that manages project milestone lifecycle.
 * @author Key Lab Technical Team.
 */
interface IMilestonesModule {
  enum MilestoneStatus {
    None,
    Proposed,
    Approved,
    Executed,
    Cancelled
  }

  struct Milestone {
    bytes32 descriptionHash;
    address token;
    address recipient;
    uint256 amount;
    MilestoneStatus status;
  }

  error ZeroAddress();
  error ZeroAmount();
  error Unauthorized();
  error InvalidMilestone();
  error InvalidState();
  error VaultPaused();
  error InvalidVaultState();
  error FundingNotFinalized();
  error InsufficientAvailableFunds();
  error InvalidToken();

  event MilestonesInitialized(address indexed vault, address indexed governance);
  event MilestoneProposed(
    uint256 indexed id, address indexed proposer, address token, address recipient, uint256 amount, string description
  );
  event MilestoneExecuted(uint256 indexed id);
  event MilestoneCancelled(uint256 indexed id);

  function initialize(address vault_, address governance_, address projectCreator_, address revenue_) external;

  function proposeMilestone(
    string calldata description,
    address token,
    address recipient,
    uint256 amount
  ) external returns (uint256);

  function executeMilestone(uint256 id) external;

  function cancelMilestone(uint256 id) external;

  function milestoneCount() external view returns (uint256);

  function milestones(uint256 id)
    external
    view
    returns (bytes32 descriptionHash, address token, address recipient, uint256 amount, MilestoneStatus status);
}
