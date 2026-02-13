// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IGovernanceModule} from "../../../interfaces/v2/IGovernanceModule.sol";
import {IProjectVault} from "../../../interfaces/v2/IProjectVault.sol";

contract GovernanceModule is Initializable, IGovernanceModule {
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant QUORUM_PERCENT = 60;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Vault address (stored as address to avoid override mismatch)
    address public override vault;

    uint256 public override proposalCount;

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

    function initialize(address vault_) external initializer {
        if (vault_ == address(0)) revert ZeroAddress();
        vault = vault_;

        emit GovernanceInitialized(vault_);
    }

    /*//////////////////////////////////////////////////////////////
                            GOVERNANCE LOGIC
    //////////////////////////////////////////////////////////////*/

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

        _executeAction(p.action);

        emit ProposalExecuted(id, p.action);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL EXECUTION
    //////////////////////////////////////////////////////////////*/

    function _executeAction(Action action) internal {
        IProjectVault v = IProjectVault(vault);

        if (action == Action.ActivateVault) {
            v.activate();
        } else if (action == Action.CloseVault) {
            v.close();
        } else if (action == Action.FreezeVault) {
            v.pause();
        } else if (action == Action.UnfreezeVault) {
            v.unpause();
        }
    }
}
