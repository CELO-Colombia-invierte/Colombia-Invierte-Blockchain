// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IGovernanceModule
 * @notice Interface for the governance module that manages proposals and voting.
 * @author Key Lab Technical Team.
 */
interface IGovernanceModule {
  /*//////////////////////////////////////////////////////////////
                              ENUMS
  //////////////////////////////////////////////////////////////*/

  enum Action {
    ActivateVault,
    CloseVault,
    FreezeFromDispute,
    UnfreezeVault,
    ApproveMilestone,
    ExecuteMilestone,
    Disbursement,
    UpdateVotingPeriod,
    UpdateQuorum
  }
  enum Vote {
    None,
    Yes,
    No
  }

  /*//////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  struct Proposal {
    Action action;
    uint256 targetId;
    uint256 startTime;
    uint256 endTime;
    uint256 snapshotBlock;
    uint256 snapshotQuorum;
    uint256 yesVotes;
    uint256 noVotes;
    uint256 amount;
    address recipient;
    address token;
    bytes32 descriptionHash;
    bool executed;
  }

  /*//////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  error ZeroAddress();
  error InvalidProposal();
  error VotingStillOpen();
  error VotingClosed();
  error AlreadyVoted();
  error AlreadyExecuted();
  error QuorumNotReached();
  error InvalidVote();
  error InvalidDisbursement();
  error Unauthorized();
  error VaultPaused();
  error InvalidVaultState();

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  event ProposalCreated(
    uint256 indexed id, address indexed proposer, address token, address recipient, uint256 amount, string description
  );
  event VoteCast(uint256 indexed id, address indexed voter, Vote vote);
  event ProposalExecuted(uint256 indexed id, Action action);
  event GovernanceInitialized(address indexed vault);
  event DisbursementExecuted(address indexed recipient, address indexed token, uint256 amount);
  event VotingPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
  event QuorumUpdated(uint256 oldQuorum, uint256 newQuorum);

  /*//////////////////////////////////////////////////////////////
                              CORE
  //////////////////////////////////////////////////////////////*/

  function initialize(address vault_, address milestones_, address votingStrategy_, address disputes_) external;

  function propose(
    Action action,
    uint256 targetId,
    uint256 amount,
    address recipient,
    address token,
    string calldata description
  ) external returns (uint256);

  function vote(uint256 proposalId, Vote vote) external;

  function execute(uint256 proposalId) external;

  function vault() external view returns (address);

  function proposalCount() external view returns (uint256);
}
