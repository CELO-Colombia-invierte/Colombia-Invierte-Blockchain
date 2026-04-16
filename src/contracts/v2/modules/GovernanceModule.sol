// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDisputesModule} from '../../../interfaces/v2/IDisputesModule.sol';
import {IGovernanceModule} from '../../../interfaces/v2/IGovernanceModule.sol';
import {IMilestonesModule} from '../../../interfaces/v2/IMilestonesModule.sol';
import {IProjectVault} from '../../../interfaces/v2/IProjectVault.sol';
import {IVotingStrategy} from '../../../interfaces/v2/IVotingStrategy.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';

/**
 * @title GovernanceModule
 * @notice Manages project governance through proposals and voting with parameter snapshots.
 * @dev Clonable via EIP-1167. Supports vault control, milestones, disbursements, and parameter updates.
 * @author Key Lab Technical Team.
 */
contract GovernanceModule is Initializable, ReentrancyGuardUpgradeable, IGovernanceModule {
  uint256 public votingPeriod;
  uint256 public quorumPercent;

  uint256 public constant MIN_VOTING_PERIOD = 1 minutes;
  uint256 public constant MAX_VOTING_PERIOD = 30 days;
  uint256 public constant MIN_QUORUM = 10;
  uint256 public constant MAX_QUORUM = 100;

  /*//////////////////////////////////////////////////////////////
                              STORAGE
  //////////////////////////////////////////////////////////////*/

  address public override vault;
  uint256 public override proposalCount;
  address public milestones;
  address public votingStrategy;
  address public disputes;

  mapping(uint256 => Proposal) public proposals;
  mapping(uint256 => mapping(address => Vote)) public votes;

  /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor() {
    _disableInitializers();
  }

  /*//////////////////////////////////////////////////////////////
                              INITIALIZER
  //////////////////////////////////////////////////////////////*/

  function initialize(
    address vault_,
    address milestones_,
    address votingStrategy_,
    address disputes_
  ) external initializer {
    if (vault_ == address(0)) revert ZeroAddress();
    if (votingStrategy_ == address(0) || disputes_ == address(0)) {
      revert ZeroAddress();
    }

    __ReentrancyGuard_init();

    vault = vault_;
    milestones = milestones_;
    votingStrategy = votingStrategy_;
    disputes = disputes_;

    votingPeriod = 1 minutes;
    quorumPercent = 60;

    emit GovernanceInitialized(vault_);
  }

  /*//////////////////////////////////////////////////////////////
                          GOVERNANCE LOGIC
  //////////////////////////////////////////////////////////////*/

  function propose(
    Action action,
    uint256 targetId,
    uint256 amount,
    address recipient,
    address token,
    string calldata description
  ) external returns (uint256 id) {
    if ((action == Action.ApproveMilestone || action == Action.ExecuteMilestone) && milestones == address(0)) revert InvalidProposal();

    if (action == Action.Disbursement) {
      if (targetId != 0) revert InvalidDisbursement();
    } else if (action == Action.ApproveMilestone || action == Action.ExecuteMilestone) {
      if (targetId == 0) revert InvalidProposal();
    }

    if (action == Action.Disbursement) {
      if (recipient == address(0) || amount == 0 || token == address(0)) {
        revert InvalidDisbursement();
      }
    } else if (action == Action.UpdateVotingPeriod || action == Action.UpdateQuorum) {
      if (recipient != address(0) || token != address(0)) {
        revert InvalidProposal();
      }
    } else {
      if (amount != 0 || recipient != address(0)) {
        revert InvalidDisbursement();
      }
    }

    if (action == Action.UpdateVotingPeriod) {
      if (amount < MIN_VOTING_PERIOD || amount > MAX_VOTING_PERIOD) {
        revert InvalidProposal();
      }
    } else if (action == Action.UpdateQuorum) {
      if (amount < MIN_QUORUM || amount > MAX_QUORUM) {
        revert InvalidProposal();
      }
    }

    id = ++proposalCount;
    bytes32 descriptionHash = keccak256(bytes(description));

    proposals[id] = Proposal({
      action: action,
      targetId: targetId,
      startTime: block.timestamp,
      endTime: block.timestamp + votingPeriod,
      snapshotBlock: block.number - 1,
      snapshotQuorum: quorumPercent,
      yesVotes: 0,
      noVotes: 0,
      amount: amount,
      recipient: recipient,
      token: token,
      descriptionHash: descriptionHash,
      executed: false
    });

    emit ProposalCreated(id, msg.sender, token, recipient, amount, description);
  }

  function vote(uint256 id, Vote vote_) external {
    Proposal storage p = proposals[id];

    if (p.startTime == 0) revert InvalidProposal();
    if (block.timestamp > p.endTime) revert VotingClosed();
    if (votes[id][msg.sender] != Vote.None) revert AlreadyVoted();
    if (vote_ == Vote.None) revert InvalidVote();

    uint256 weight = IVotingStrategy(votingStrategy).getVotingPower(msg.sender, p.snapshotBlock);
    if (weight == 0) revert Unauthorized();

    votes[id][msg.sender] = vote_;
    if (vote_ == Vote.Yes) p.yesVotes += weight;
    else p.noVotes += weight;

    emit VoteCast(id, msg.sender, vote_);
  }

  function execute(uint256 id) external nonReentrant {
    Proposal storage p = proposals[id];

    if (p.startTime == 0) revert InvalidProposal();
    if (p.executed) revert AlreadyExecuted();
    if (block.timestamp <= p.endTime) revert VotingStillOpen();
    if (vault == address(0)) revert InvalidProposal();

    uint256 totalVotes = p.yesVotes + p.noVotes;
    if (totalVotes == 0) revert QuorumNotReached();

    uint256 yesPercent = (p.yesVotes * 100) / totalVotes;
    if (yesPercent < p.snapshotQuorum) revert QuorumNotReached();

    p.executed = true;
    _executeAction(p);
    emit ProposalExecuted(id, p.action);
  }

  /*//////////////////////////////////////////////////////////////
                          INTERNAL EXECUTION
  //////////////////////////////////////////////////////////////*/

  function _executeAction(Proposal storage p) internal {
    IProjectVault v = IProjectVault(vault);

    if (p.action != Action.UnfreezeVault && p.action != Action.FreezeFromDispute) {
      if (v.paused()) revert VaultPaused();
    }

    if (p.action == Action.Disbursement || p.action == Action.ExecuteMilestone) {
      if (v.state() != IProjectVault.VaultState.Active) {
        revert InvalidVaultState();
      }
    }

    if (p.action == Action.ActivateVault) {
      v.activate();
    } else if (p.action == Action.CloseVault) {
      v.close();
    } else if (p.action == Action.FreezeFromDispute) {
      IDisputesModule(disputes).markFrozen(p.targetId);
      v.freezeByDispute(p.targetId);
    } else if (p.action == Action.UnfreezeVault) {
      if (v.activeDisputeId() != 0) {
        v.unfreezeFromDispute();
      } else {
        v.unpause();
      }
    } else if (p.action == Action.ApproveMilestone) {
      if (milestones == address(0)) revert InvalidProposal();
      IMilestonesModule(milestones).approveMilestone(p.targetId);
    } else if (p.action == Action.ExecuteMilestone) {
      if (milestones == address(0)) revert InvalidProposal();
      IMilestonesModule(milestones).executeMilestone(p.targetId);
    } else if (p.action == Action.Disbursement) {
      if (!v.isTokenAllowed(p.token)) revert InvalidDisbursement();
      v.release(p.token, p.recipient, p.amount);
      emit DisbursementExecuted(p.recipient, p.token, p.amount);
    } else if (p.action == Action.UpdateVotingPeriod) {
      uint256 oldPeriod = votingPeriod;
      votingPeriod = p.amount;
      emit VotingPeriodUpdated(oldPeriod, p.amount);
    } else if (p.action == Action.UpdateQuorum) {
      uint256 oldQuorum = quorumPercent;
      quorumPercent = p.amount;
      emit QuorumUpdated(oldQuorum, p.amount);
    }
  }
}
