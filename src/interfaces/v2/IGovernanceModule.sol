// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IGovernanceModule
 * @notice Interface for the governance module that manages proposals and voting.
 */
interface IGovernanceModule {
    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/

    enum Action {
        ActivateVault,
        CloseVault,
        FreezeVault,
        UnfreezeVault,
        ApproveMilestone,
        ExecuteMilestone
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
        uint256 targetId; // For milestones
        uint256 startTime;
        uint256 yesVotes;
        uint256 noVotes;
        bool executed;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProposalCreated(uint256 indexed id, Action action);
    event VoteCast(uint256 indexed id, address indexed voter, Vote vote);
    event ProposalExecuted(uint256 indexed id, Action action);

    /*//////////////////////////////////////////////////////////////
                                CORE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the governance module with vault and milestones addresses.
     * @param vault_ Address of the associated ProjectVault
     * @param milestones_ Address of the milestones module
     */
    function initialize(address vault_, address milestones_) external;

    /**
     * @notice Creates a new proposal for a specific action.
     * @param action Type of action to execute
     * @param targetId ID of the milestone target (ignored for vault actions)
     * @return id Unique identifier for the created proposal
     */
    function propose(
        Action action,
        uint256 targetId
    ) external returns (uint256);

    /**
     * @notice Casts a vote on an active proposal.
     * @param proposalId ID of the proposal to vote on
     * @param vote Vote choice (Yes or No)
     */
    function vote(uint256 proposalId, Vote vote) external;

    /**
     * @notice Executes a proposal after voting period ends and quorum is met.
     * @param proposalId ID of the proposal to execute
     */
    function execute(uint256 proposalId) external;

    /*//////////////////////////////////////////////////////////////
                                VIEW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the vault address associated with this governance module.
     * @return vault Address of the ProjectVault
     */
    function vault() external view returns (address);

    /**
     * @notice Returns the total number of proposals created.
     * @return proposalCount Total proposals
     */
    function proposalCount() external view returns (uint256);
}
