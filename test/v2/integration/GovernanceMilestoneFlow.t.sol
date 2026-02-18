// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {PlatformV2} from "../../../src/contracts/v2/core/PlatformV2.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
import {GovernanceModule} from "../../../src/contracts/v2/modules/GovernanceModule.sol";
import {DisputesModule} from "../../../src/contracts/v2/modules/DisputesModule.sol";
import {MilestonesModule} from "../../../src/contracts/v2/modules/MilestonesModule.sol";

import {IGovernanceModule} from "../../../src/interfaces/v2/IGovernanceModule.sol";
import {IMilestonesModule} from "../../../src/interfaces/v2/IMilestonesModule.sol";

import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";

contract MockProject {}

/**
 * @title GovernanceMilestoneFlowTest
 * @notice Integration tests for governance-controlled milestone flow.
 */
contract GovernanceMilestoneFlowTest is Test {
    PlatformV2 platform;

    ProjectVault vaultImpl;
    GovernanceModule governanceImpl;
    DisputesModule disputesImpl;
    MilestonesModule milestonesImpl;

    address voter1 = address(0x1);
    address voter2 = address(0x2);

    function setUp() public {
        vaultImpl = new ProjectVault();
        governanceImpl = new GovernanceModule();
        disputesImpl = new DisputesModule();
        milestonesImpl = new MilestonesModule();

        platform = new PlatformV2(
            address(vaultImpl),
            address(governanceImpl),
            address(disputesImpl),
            address(milestonesImpl)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _activateVault(IGovernanceModule governance) internal {
        uint256 id = governance.propose(
            IGovernanceModule.Action.ActivateVault,
            0
        );

        vm.prank(voter1);
        governance.vote(id, IGovernanceModule.Vote.Yes);

        vm.prank(voter2);
        governance.vote(id, IGovernanceModule.Vote.Yes);

        vm.warp(block.timestamp + 3 days + 1);
        governance.execute(id);
    }

    function _voteYes(
        IGovernanceModule governance,
        uint256 proposalId
    ) internal {
        vm.prank(voter1);
        governance.vote(proposalId, IGovernanceModule.Vote.Yes);

        vm.prank(voter2);
        governance.vote(proposalId, IGovernanceModule.Vote.Yes);
    }

    /*//////////////////////////////////////////////////////////////
                        1️⃣ HAPPY PATH
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests successful milestone flow: propose, approve, execute.
     */
    function testMilestoneThroughGovernanceFlow() public {
        MockProject project = new MockProject();
        uint256 id = platform.createProject(address(project));

        (
            address vaultAddr,
            address governanceAddr,
            address disputesAddr,
            ,
            address milestonesAddr
        ) = platform.projects(id);

        IGovernanceModule governance = IGovernanceModule(governanceAddr);
        IMilestonesModule milestones = IMilestonesModule(milestonesAddr);

        _activateVault(governance);

        // Token setup
        MockERC20 token = new MockERC20("Mock", "MOCK");
        token.mint(address(this), 1_000_000 ether);

        vm.prank(disputesAddr);
        ProjectVault(vaultAddr).setTokenAllowed(address(token), true);

        bool success = token.transfer(vaultAddr, 100 ether);
        require(success);

        // Propose milestone
        vm.prank(governanceAddr);
        uint256 milestoneId = milestones.proposeMilestone(
            "Phase 1",
            address(token),
            address(0x3),
            50 ether
        );

        // Governance approves milestone
        uint256 approveId = governance.propose(
            IGovernanceModule.Action.ApproveMilestone,
            milestoneId
        );

        _voteYes(governance, approveId);
        vm.warp(block.timestamp + 3 days + 1);
        governance.execute(approveId);

        // Governance executes milestone
        uint256 execId = governance.propose(
            IGovernanceModule.Action.ExecuteMilestone,
            milestoneId
        );

        _voteYes(governance, execId);
        vm.warp(block.timestamp + 3 days + 1);
        governance.execute(execId);

        assertEq(token.balanceOf(address(0x3)), 50 ether);
    }

    /*//////////////////////////////////////////////////////////////
                2️⃣ CANNOT EXECUTE BEFORE APPROVAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that execution fails if milestone is not approved.
     */
    function testCannotExecuteMilestoneWithoutApproval() public {
        MockProject project = new MockProject();
        uint256 id = platform.createProject(address(project));

        (
            address vaultAddr,
            address governanceAddr,
            address disputesAddr,
            ,
            address milestonesAddr
        ) = platform.projects(id);

        IGovernanceModule governance = IGovernanceModule(governanceAddr);
        IMilestonesModule milestones = IMilestonesModule(milestonesAddr);

        _activateVault(governance);

        MockERC20 token = new MockERC20("Mock", "MOCK");
        token.mint(address(this), 1_000_000 ether);

        vm.prank(disputesAddr);
        ProjectVault(vaultAddr).setTokenAllowed(address(token), true);

        bool success = token.transfer(vaultAddr, 100 ether);
        require(success);

        vm.prank(governanceAddr);
        uint256 milestoneId = milestones.proposeMilestone(
            "Phase 1",
            address(token),
            address(0x3),
            50 ether
        );

        uint256 execId = governance.propose(
            IGovernanceModule.Action.ExecuteMilestone,
            milestoneId
        );

        _voteYes(governance, execId);
        vm.warp(block.timestamp + 3 days + 1);

        vm.expectRevert();
        governance.execute(execId);
    }

    /*//////////////////////////////////////////////////////////////
                3️⃣ CANNOT EXECUTE BEFORE VOTING ENDS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that execution fails if voting period is still active.
     */
    function testCannotExecuteBeforeVotingPeriodEnds() public {
        MockProject project = new MockProject();
        uint256 id = platform.createProject(address(project));

        (, address governanceAddr, , , ) = platform.projects(id);

        IGovernanceModule governance = IGovernanceModule(governanceAddr);

        uint256 proposalId = governance.propose(
            IGovernanceModule.Action.ActivateVault,
            0
        );

        _voteYes(governance, proposalId);

        vm.expectRevert();
        governance.execute(proposalId);
    }

    /*//////////////////////////////////////////////////////////////
                4️⃣ CANNOT EXECUTE TWICE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that a proposal cannot be executed more than once.
     */
    function testCannotExecuteTwice() public {
        MockProject project = new MockProject();
        uint256 id = platform.createProject(address(project));

        (, address governanceAddr, , , ) = platform.projects(id);

        IGovernanceModule governance = IGovernanceModule(governanceAddr);

        uint256 proposalId = governance.propose(
            IGovernanceModule.Action.ActivateVault,
            0
        );

        _voteYes(governance, proposalId);
        vm.warp(block.timestamp + 3 days + 1);

        governance.execute(proposalId);

        vm.expectRevert();
        governance.execute(proposalId);
    }
}
