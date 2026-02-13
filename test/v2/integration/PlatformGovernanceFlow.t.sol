// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {PlatformV2} from "../../../src/contracts/v2/core/PlatformV2.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
import {GovernanceModule} from "../../../src/contracts/v2/modules/GovernanceModule.sol";
import {DisputesModule} from "../../../src/contracts/v2/modules/DisputesModule.sol";
import {IGovernanceModule} from "../../../src/interfaces/v2/IGovernanceModule.sol";
import {IProjectVault} from "../../../src/interfaces/v2/IProjectVault.sol";

contract MockProject {}

contract PlatformGovernanceFlowTest is Test {
    PlatformV2 platform;
    ProjectVault vaultImpl;
    GovernanceModule governanceImpl;
    DisputesModule disputesImpl;

    address voter1 = address(0x1);
    address voter2 = address(0x2);

    function setUp() public {
        vaultImpl = new ProjectVault();
        governanceImpl = new GovernanceModule();
        disputesImpl = new DisputesModule();

        platform = new PlatformV2(
            address(vaultImpl),
            address(governanceImpl),
            address(disputesImpl)
        );
    }

    function testVaultRolesAreCorrect() public {
        MockProject project = new MockProject();

        uint256 id = platform.createProject(address(project));

        (
            address vaultAddr,
            address governanceAddr,
            address disputesAddr,

        ) = platform.projects(id);

        ProjectVault vault = ProjectVault(vaultAddr);

        assertTrue(vault.hasRole(vault.GOVERNANCE_ROLE(), governanceAddr));

        assertTrue(vault.hasRole(vault.GUARDIAN_ROLE(), disputesAddr));

        assertTrue(vault.hasRole(vault.CONTROLLER_ROLE(), address(project)));
    }

    function testGovernanceActivatesVault() public {
        MockProject project = new MockProject();
        uint256 id = platform.createProject(address(project));

        (address vaultAddr, address governanceAddr, , ) = platform.projects(id);

        IProjectVault vault = IProjectVault(vaultAddr);
        IGovernanceModule governance = IGovernanceModule(governanceAddr);

        uint256 proposalId = governance.propose(
            IGovernanceModule.Action.ActivateVault
        );

        vm.prank(address(1));
        governance.vote(proposalId, IGovernanceModule.Vote.Yes);

        vm.prank(address(2));
        governance.vote(proposalId, IGovernanceModule.Vote.Yes);

        vm.warp(block.timestamp + 3 days + 1);

        governance.execute(proposalId);

        assertEq(uint256(vault.state()), 1); // Active
    }

    function testDisputeFreezesVault() public {
        MockProject project = new MockProject();
        uint256 id = platform.createProject(address(project));

        (
            address vaultAddr,
            address governanceAddr,
            address disputesAddr,

        ) = platform.projects(id);

        IProjectVault vault = IProjectVault(vaultAddr);
        IGovernanceModule governance = IGovernanceModule(governanceAddr);
        DisputesModule disputes = DisputesModule(disputesAddr);

        // Activar primero
        uint256 proposalId = governance.propose(
            IGovernanceModule.Action.ActivateVault
        );

        vm.prank(address(1));
        governance.vote(proposalId, IGovernanceModule.Vote.Yes);

        vm.prank(address(2));
        governance.vote(proposalId, IGovernanceModule.Vote.Yes);

        vm.warp(block.timestamp + 3 days + 1);
        governance.execute(proposalId);

        assertEq(uint256(vault.state()), 1);

        // Abrir disputa
        disputes.openDispute("Fraud suspected");

        ProjectVault concreteVault = ProjectVault(vaultAddr);
        assertTrue(concreteVault.paused());
    }

    function testProjectsAreIsolated() public {
        MockProject p1 = new MockProject();
        MockProject p2 = new MockProject();

        uint256 id1 = platform.createProject(address(p1));
        uint256 id2 = platform.createProject(address(p2));

        (address v1, , , ) = platform.projects(id1);
        (address v2, , , ) = platform.projects(id2);

        assertTrue(v1 != v2);
    }
}
