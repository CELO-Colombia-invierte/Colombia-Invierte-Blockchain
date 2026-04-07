// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IGovernanceModule} from "../../../interfaces/v2/IGovernanceModule.sol";
import {IProjectVault} from "../../../interfaces/v2/IProjectVault.sol";
import {IMilestonesModule} from "../../../interfaces/v2/IMilestonesModule.sol";
import {IVotingStrategy} from "../../../interfaces/v2/IVotingStrategy.sol";

/**
 * @title GovernanceModule
 * @notice Manages project governance through proposals and voting.
 * @dev Clonable via EIP-1167. Proposals can control vault state and milestone progression.
 * @author Key Lab Technical Team.
 */
contract GovernanceModule is Initializable, IGovernanceModule {
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant QUORUM_PERCENT = 60;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public override vault;
    uint256 public override proposalCount;
    address public milestones;
    address public votingStrategy;

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => Vote)) public votes;

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the governance module with vault and milestones addresses.
     */
    function initialize(
        address vault_,
        address milestones_,
        address votingStrategy_
    ) external initializer {
        if (vault_ == address(0)) revert ZeroAddress();
        if (milestones_ == address(0)) revert ZeroAddress();
        if (votingStrategy_ == address(0)) revert ZeroAddress();

        vault = vault_;
        milestones = milestones_;
        votingStrategy = votingStrategy_;

        emit GovernanceInitialized(vault_);
    }

    /*//////////////////////////////////////////////////////////////
                            GOVERNANCE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new proposal for a specific action.
     * @param targetId ID of the milestone target (ignored for vault actions)
     */
    function propose(
        Action action,
        uint256 targetId,
        uint256 amount,
        address recipient,
        address token,
        string calldata description
    ) external returns (uint256 id) {
        if (
            (action == Action.ApproveMilestone ||
                action == Action.ExecuteMilestone) && milestones == address(0)
        ) revert InvalidProposal();

        if (action == Action.Disbursement) {
            if (targetId != 0) revert InvalidDisbursement();
        } else if (
            action == Action.ApproveMilestone ||
            action == Action.ExecuteMilestone
        ) {
            if (targetId == 0) revert InvalidProposal();
        }

        if (action == Action.Disbursement) {
            if (recipient == address(0) || amount == 0 || token == address(0)) {
                revert InvalidDisbursement();
            }
        } else {
            if (amount != 0 || recipient != address(0)) {
                revert InvalidDisbursement();
            }
        }
        id = ++proposalCount;
        bytes32 descriptionHash = keccak256(bytes(description));
        proposals[id] = Proposal({
            action: action,
            targetId: targetId,
            startTime: block.timestamp,
            snapshotBlock: block.number - 1,
            yesVotes: 0,
            noVotes: 0,
            amount: amount,
            recipient: recipient,
            token: token,
            descriptionHash: descriptionHash,
            executed: false
        });
        emit ProposalCreated(
            id,
            msg.sender,
            token,
            recipient,
            amount,
            description
        );
    }

    /**
     * @notice Casts a vote on an active proposal.
     */
    function vote(uint256 id, Vote vote_) external {
        Proposal storage p = proposals[id];

        if (p.startTime == 0) revert InvalidProposal();
        if (block.timestamp > p.startTime + VOTING_PERIOD)
            revert VotingClosed();
        if (votes[id][msg.sender] != Vote.None) revert AlreadyVoted();
        if (vote_ == Vote.None) revert InvalidVote();
        uint256 weight = IVotingStrategy(votingStrategy).getVotingPower(
            msg.sender,
            p.snapshotBlock
        );

        if (weight == 0) revert Unauthorized();

        votes[id][msg.sender] = vote_;
        if (vote_ == Vote.Yes) p.yesVotes += weight;
        else p.noVotes += weight;

        emit VoteCast(id, msg.sender, vote_);
    }

    /**
     * @notice Executes a proposal after voting period ends and quorum is met.
     * @dev Requires >60% yes votes from total votes cast.
     */
    function execute(uint256 id) external {
        Proposal storage p = proposals[id];

        if (p.startTime == 0) revert InvalidProposal();
        if (p.executed) revert AlreadyExecuted();
        if (block.timestamp <= p.startTime + VOTING_PERIOD)
            revert VotingStillOpen();
        if (vault == address(0)) revert InvalidProposal();

        uint256 totalVotes = p.yesVotes + p.noVotes;
        if (totalVotes == 0) revert QuorumNotReached();

        uint256 yesPercent = (p.yesVotes * 100) / totalVotes;
        if (yesPercent < QUORUM_PERCENT) revert QuorumNotReached();

        p.executed = true;
        _executeAction(p);
        emit ProposalExecuted(id, p.action);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL EXECUTION
    //////////////////////////////////////////////////////////////*/

    function _executeAction(Proposal storage p) internal {
        IProjectVault v = IProjectVault(vault);

        if (p.action == Action.ActivateVault) {
            v.activate();
        } else if (p.action == Action.CloseVault) {
            v.close();
        } else if (p.action == Action.FreezeVault) {
            v.pause();
        } else if (p.action == Action.UnfreezeVault) {
            v.unpause();
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
        }
    }
}
