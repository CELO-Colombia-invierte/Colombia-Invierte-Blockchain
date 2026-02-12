// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {GovernanceModule} from "../../src/contracts/v2/modules/GovernanceModule.sol";
import {IGovernanceModule} from "../../src/interfaces/v2/IGovernanceModule.sol";

/*//////////////////////////////////////////////////////////////
                        MOCK VAULT
//////////////////////////////////////////////////////////////*/
/*
 * @notice Mock contract for testing the GovernanceModule contract. It simulates a project vault with basic state changes that can be triggered by governance proposals.
 */
contract MockProjectVault {
    bool public activated;
    bool public closed;
    bool public paused;

    function activate() external {
        activated = true;
    }

    function close() external {
        closed = true;
    }

    function pause() external {
        paused = true;
    }

    function unpause() external {
        paused = false;
    }
}

/*//////////////////////////////////////////////////////////////
                    GOVERNANCE MODULE TEST
//////////////////////////////////////////////////////////////*/
/*
 * @notice Test suite for the GovernanceModule contract, covering proposal creation, voting, and execution logic.
 */
contract GovernanceModuleTest is Test {
    GovernanceModule gov;
    MockProjectVault vault;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCAFE);

    function setUp() external {
        vault = new MockProjectVault();
        gov = new GovernanceModule(address(vault));
    }

    /*//////////////////////////////////////////////////////////////
                            PROPOSE
    //////////////////////////////////////////////////////////////*/
    /*
     * @notice Tests that proposing an action creates a new proposal with the correct details.
     */
    function testProposeCreatesProposal() external {
        uint256 id = gov.propose(IGovernanceModule.Action.ActivateVault);

        (
            IGovernanceModule.Action action,
            uint256 startTime,
            uint256 yesVotes,
            uint256 noVotes,
            bool executed
        ) = gov.proposals(id);

        assertEq(
            uint256(action),
            uint256(IGovernanceModule.Action.ActivateVault)
        );
        assertGt(startTime, 0);
        assertEq(yesVotes, 0);
        assertEq(noVotes, 0);
        assertFalse(executed);
    }

    /*//////////////////////////////////////////////////////////////
                            VOTING
    //////////////////////////////////////////////////////////////*/
    /*
     * @notice Tests that voting "Yes" on a proposal increments the yesVotes count.
     */
    function testVoteYesIncrementsYesVotes() external {
        uint256 id = gov.propose(IGovernanceModule.Action.ActivateVault);

        vm.prank(alice);
        gov.vote(id, IGovernanceModule.Vote.Yes);

        (, , uint256 yesVotes, , ) = gov.proposals(id);
        assertEq(yesVotes, 1);
    }

    /*
     * @notice Tests that voting "No" on a proposal increments the noVotes count.
     */
    function testVoteNoIncrementsNoVotes() external {
        uint256 id = gov.propose(IGovernanceModule.Action.ActivateVault);

        vm.prank(bob);
        gov.vote(id, IGovernanceModule.Vote.No);

        (, , , uint256 noVotes, ) = gov.proposals(id);
        assertEq(noVotes, 1);
    }

    /*
     * @notice Tests that a user cannot vote more than once on the same proposal.
     */
    function testCannotVoteTwice() external {
        uint256 id = gov.propose(IGovernanceModule.Action.ActivateVault);

        vm.prank(alice);
        gov.vote(id, IGovernanceModule.Vote.Yes);

        vm.prank(alice);
        vm.expectRevert(GovernanceModule.AlreadyVoted.selector);
        gov.vote(id, IGovernanceModule.Vote.Yes);
    }

    /*
     * @notice Tests that a user cannot vote after the voting period has ended.
     */
    function testCannotVoteAfterVotingPeriod() external {
        uint256 id = gov.propose(IGovernanceModule.Action.ActivateVault);

        vm.warp(block.timestamp + gov.VOTING_PERIOD() + 1);

        vm.prank(alice);
        vm.expectRevert(GovernanceModule.VotingClosed.selector);
        gov.vote(id, IGovernanceModule.Vote.Yes);
    }

    /*//////////////////////////////////////////////////////////////
                            EXECUTION
    //////////////////////////////////////////////////////////////*/
    /*
     * @notice Tests that a proposal cannot be executed if it does not have enough yes votes to reach quorum.
     */
    function testCannotExecuteBeforeVotingEnds() external {
        uint256 id = gov.propose(IGovernanceModule.Action.ActivateVault);

        vm.prank(alice);
        gov.vote(id, IGovernanceModule.Vote.Yes);

        vm.expectRevert(GovernanceModule.VotingClosed.selector);
        gov.execute(id);
    }

    /*
     * @notice Tests that a proposal cannot be executed if it does not have enough yes votes to reach quorum.
     */
    function testCannotExecuteWithoutQuorum() external {
        uint256 id = gov.propose(IGovernanceModule.Action.ActivateVault);

        vm.prank(alice);
        gov.vote(id, IGovernanceModule.Vote.No);

        vm.warp(block.timestamp + gov.VOTING_PERIOD() + 1);

        vm.expectRevert(GovernanceModule.QuorumNotReached.selector);
        gov.execute(id);
    }

    /*
     * @notice Tests that a proposal can be executed successfully when it has enough yes votes.
     */
    function testExecuteActivateVault() external {
        uint256 id = gov.propose(IGovernanceModule.Action.ActivateVault);

        vm.prank(alice);
        gov.vote(id, IGovernanceModule.Vote.Yes);

        vm.prank(bob);
        gov.vote(id, IGovernanceModule.Vote.Yes);

        vm.warp(block.timestamp + gov.VOTING_PERIOD() + 1);

        gov.execute(id);

        assertTrue(vault.activated());
    }

    /**
     * @notice Tests that a proposal cannot be executed more than once.
     */
    function testCannotExecuteTwice() external {
        uint256 id = gov.propose(IGovernanceModule.Action.ActivateVault);

        vm.prank(alice);
        gov.vote(id, IGovernanceModule.Vote.Yes);

        vm.prank(bob);
        gov.vote(id, IGovernanceModule.Vote.Yes);

        vm.warp(block.timestamp + gov.VOTING_PERIOD() + 1);

        gov.execute(id);

        vm.expectRevert(GovernanceModule.AlreadyExecuted.selector);
        gov.execute(id);
    }
}
