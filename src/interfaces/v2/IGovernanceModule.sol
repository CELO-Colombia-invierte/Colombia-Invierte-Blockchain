// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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

    function initialize(address vault_, address milestones_) external;

    function propose(
        Action action,
        uint256 targetId
    ) external returns (uint256);

    function vote(uint256 proposalId, Vote vote) external;

    function execute(uint256 proposalId) external;

    /*//////////////////////////////////////////////////////////////
                                VIEW
    //////////////////////////////////////////////////////////////*/

    function vault() external view returns (address);

    function proposalCount() external view returns (uint256);
}
