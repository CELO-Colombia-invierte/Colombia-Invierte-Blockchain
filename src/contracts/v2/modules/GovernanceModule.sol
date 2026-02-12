// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IGovernanceModule} from "../../../interfaces/v2/IGovernanceModule.sol";
import {IProjectVault} from "../../../interfaces/v2/IProjectVault.sol";

/**
 * @title GovernanceModule
 * @notice Implementation of the IGovernanceModule interface, allowing users to propose and vote on actions related to vault management.
 */
contract GovernanceModule is IGovernanceModule {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Duration of the voting period for each proposal.
    uint256 public constant VOTING_PERIOD = 3 days;
    /// @notice Minimum percentage of yes votes required for a proposal to pass.
    uint256 public constant QUORUM_PERCENT = 60;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @notice Reference to the associated Project Vault that this governance module manages.
    IProjectVault public immutable vault;

    /// @notice Counter for proposal IDs, incremented each time a new proposal is created.
    uint256 public proposalCount;
    /// @notice Mapping of proposal ID to Proposal details.
    mapping(uint256 => Proposal) public proposals;
    /// @notice Mapping to track votes cast by each address for each proposal.
    mapping(uint256 => mapping(address => Vote)) public votes;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    /// @notice Error thrown when an invalid proposal ID is referenced.
    error InvalidProposal();
    /// @notice Error thrown when trying to vote after the voting period has ended.
    error VotingClosed();
    /// @notice Error thrown when an address tries to vote more than once on the same proposal.
    error AlreadyVoted();
    /// @notice Error thrown when a proposal does not have enough votes to pass.
    error QuorumNotReached();
    /// @notice Error thrown when trying to execute a proposal that has already been executed.
    error AlreadyExecuted();

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Initializes the Governance Module with a reference to the associated Project Vault.
     * @param vault_ The address of the Project Vault that this governance module will manage.
     */
    constructor(address vault_) {
        vault = IProjectVault(vault_);
    }

    /*//////////////////////////////////////////////////////////////
                            GOVERNANCE LOGIC
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Creates a new proposal for a specific action related to vault management.
     * @param action The action being proposed (e.g., ActivateVault, CloseVault).
     * @return id The unique ID of the newly created proposal.
     */
    function propose(Action action) external returns (uint256 id) {
        id = ++proposalCount;

        proposals[id] = Proposal({
            action: action,
            startTime: block.timestamp,
            yesVotes: 0,
            noVotes: 0,
            executed: false
        });

        emit ProposalCreated(id, action);
    }

    /**
     * @notice Casts a vote on an active proposal. Each address can only vote once per proposal, and the voting period must be open.
     * @param id The ID of the proposal being voted on.
     */
    function vote(uint256 id, Vote vote_) external {
        Proposal storage p = proposals[id];
        if (p.startTime == 0) revert InvalidProposal();
        if (block.timestamp > p.startTime + VOTING_PERIOD)
            revert VotingClosed();
        if (votes[id][msg.sender] != Vote.None) revert AlreadyVoted();
        if (vote_ == Vote.None) revert();

        votes[id][msg.sender] = vote_;

        if (vote_ == Vote.Yes) p.yesVotes++;
        else p.noVotes++;

        emit VoteCast(id, msg.sender, vote_);
    }

    /**
     * @notice Executes a proposal that has passed the voting process. The proposal must not have been executed before, and the voting period must have ended.
     * @param id The ID of the proposal to execute.
     */
    function execute(uint256 id) external {
        Proposal storage p = proposals[id];
        if (p.executed) revert AlreadyExecuted();
        if (block.timestamp <= p.startTime + VOTING_PERIOD)
            revert VotingClosed();

        uint256 totalVotes = p.yesVotes + p.noVotes;
        if (totalVotes == 0) revert QuorumNotReached();

        uint256 yesPercent = (p.yesVotes * 100) / totalVotes;
        if (yesPercent < QUORUM_PERCENT) revert QuorumNotReached();

        p.executed = true;

        _executeAction(p.action);

        emit ProposalExecuted(id, p.action);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Internal function to execute the action associated with a proposal. This function is called after a proposal has been successfully executed.
     * @param action The action to execute (e.g., ActivateVault, CloseVault).
     */
    function _executeAction(Action action) internal {
        if (action == Action.ActivateVault) {
            vault.activate();
        } else if (action == Action.CloseVault) {
            vault.close();
        } else if (action == Action.FreezeVault) {
            vault.pause();
        } else if (action == Action.UnfreezeVault) {
            vault.unpause();
        }
    }
}
