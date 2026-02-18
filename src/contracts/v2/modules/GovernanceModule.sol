// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IGovernanceModule} from "../../../interfaces/v2/IGovernanceModule.sol";
import {IProjectVault} from "../../../interfaces/v2/IProjectVault.sol";
import {IMilestonesModule} from "../../../interfaces/v2/IMilestonesModule.sol";

/**
 * @title GovernanceModule
 * @notice Manages project governance through proposals and voting.
 * @dev Clonable via EIP-1167. Proposals can control vault state and milestone progression.
 */
contract GovernanceModule is Initializable, IGovernanceModule {
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant QUORUM_PERCENT = 60;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Vault address (stored as address to avoid override mismatch)
    address public override vault;

    uint256 public override proposalCount;

    address public milestones;

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => Vote)) public votes;

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

    event GovernanceInitialized(address indexed vault);

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the governance module with vault and milestones addresses.
     * @param vault_ Address of the associated ProjectVault
     * @param milestones_ Address of the milestones module
     */
    function initialize(
        address vault_,
        address milestones_
    ) external initializer {
        if (vault_ == address(0) || milestones_ == address(0))
            revert ZeroAddress();

        vault = vault_;
        milestones = milestones_;

        emit GovernanceInitialized(vault_);
    }

    /*//////////////////////////////////////////////////////////////
                            GOVERNANCE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new proposal for a specific action.
     * @param action Type of action to execute (vault control or milestone)
     * @param targetId ID of the milestone target (ignored for vault actions)
     * @return id Unique identifier for the created proposal
     */
    function propose(
        Action action,
        uint256 targetId
    ) external returns (uint256 id) {
        id = ++proposalCount;

        proposals[id] = Proposal({
            action: action,
            targetId: targetId,
            startTime: block.timestamp,
            yesVotes: 0,
            noVotes: 0,
            executed: false
        });

        emit ProposalCreated(id, action);
    }

    /**
     * @notice Casts a vote on an active proposal.
     * @param id ID of the proposal to vote on
     * @param vote_ Vote choice (Yes or No)
     */
    function vote(uint256 id, Vote vote_) external {
        Proposal storage p = proposals[id];

        if (p.startTime == 0) revert InvalidProposal();
        if (block.timestamp > p.startTime + VOTING_PERIOD)
            revert VotingClosed();
        if (votes[id][msg.sender] != Vote.None) revert AlreadyVoted();
        if (vote_ == Vote.None) revert InvalidVote();

        votes[id][msg.sender] = vote_;

        if (vote_ == Vote.Yes) {
            p.yesVotes++;
        } else {
            p.noVotes++;
        }

        emit VoteCast(id, msg.sender, vote_);
    }

    /**
     * @notice Executes a proposal after voting period ends and quorum is met.
     * @param id ID of the proposal to execute
     */
    function execute(uint256 id) external {
        Proposal storage p = proposals[id];

        if (p.startTime == 0) revert InvalidProposal();
        if (p.executed) revert AlreadyExecuted();
        if (block.timestamp <= p.startTime + VOTING_PERIOD)
            revert VotingStillOpen();

        uint256 totalVotes = p.yesVotes + p.noVotes;
        if (totalVotes == 0) revert QuorumNotReached();

        uint256 yesPercent = (p.yesVotes * 100) / totalVotes;
        if (yesPercent < QUORUM_PERCENT) revert QuorumNotReached();

        p.executed = true;

        _executeAction(p.action, p.targetId);

        emit ProposalExecuted(id, p.action);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL EXECUTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Executes the approved action on the target contract.
     */
    function _executeAction(Action action, uint256 targetId) internal {
        IProjectVault v = IProjectVault(vault);

        if (action == Action.ActivateVault) {
            v.activate();
        } else if (action == Action.CloseVault) {
            v.close();
        } else if (action == Action.FreezeVault) {
            v.pause();
        } else if (action == Action.UnfreezeVault) {
            v.unpause();
        } else if (action == Action.ApproveMilestone) {
            IMilestonesModule(milestones).approveMilestone(targetId);
        } else if (action == Action.ExecuteMilestone) {
            IMilestonesModule(milestones).executeMilestone(targetId);
        }
    }
}
