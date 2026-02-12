// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IGovernanceModule
 * @notice Interface for the Governance Module, which allows users to propose and vote on actions related to vault management.
 */

interface IGovernanceModule {
    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Actions that can be proposed and voted on by the community.
     * @dev These actions include activating, closing, freezing, or unfreezing a vault.
     */
    enum Action {
        ActivateVault,
        CloseVault,
        FreezeVault,
        UnfreezeVault
    }

    /**
     * @notice Votes that can be cast on a proposal.
     */
    enum Vote {
        None,
        Yes,
        No
    }

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Structure representing a proposal in the governance system.
     * @param action The action being proposed (e.g., ActivateVault, CloseVault).
     * @param startTime The timestamp when the proposal was created.
     * @param yesVotes The number of votes in favor of the proposal.
     * @param noVotes The number of votes against the proposal.
     * @param executed Whether the proposal has been executed or not.
     */
    struct Proposal {
        Action action;
        uint256 startTime;
        uint256 yesVotes;
        uint256 noVotes;
        bool executed;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Emitted when a new proposal is created.
    event ProposalCreated(uint256 indexed id, Action action);
    /// @notice Emitted when a vote is cast on a proposal.
    event VoteCast(uint256 indexed id, address indexed voter, Vote vote);
    /// @notice Emitted when a proposal is executed.
    event ProposalExecuted(uint256 indexed id, Action action);

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /** @notice Propose a new action for the vault.
     * @param action The action being proposed (e.g., ActivateVault, CloseVault).
     * @return proposalId The ID of the newly created proposal.
     */
    function propose(Action action) external returns (uint256);

    /** @notice Cast a vote on an active proposal.
     * @param proposalId The ID of the proposal being voted on.
     * @param vote The vote being cast (Yes, No).
     */
    function vote(uint256 proposalId, Vote vote) external;

    /** @notice Execute a proposal that has passed the voting process.
     * @param proposalId The ID of the proposal to execute.
     */
    function execute(uint256 proposalId) external;
}
