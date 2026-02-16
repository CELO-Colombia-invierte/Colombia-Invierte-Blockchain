// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {PlatformV2} from "../../../src/contracts/v2/core/PlatformV2.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
import {GovernanceModule} from "../../../src/contracts/v2/modules/GovernanceModule.sol";
import {DisputesModule} from "../../../src/contracts/v2/modules/DisputesModule.sol";
import {MilestonesModule} from "../../../src/contracts/v2/modules/MilestonesModule.sol";
import {IProjectVault} from "../../../src/interfaces/v2/IProjectVault.sol";

/// @dev Minimal mock to simulate tokenized project
contract MockProject {

}

contract PlatformV2Test is Test {
    PlatformV2 platform;
    ProjectVault vaultImpl;
    GovernanceModule governanceImpl;
    DisputesModule disputesImpl;
    MilestonesModule milestonesImpl;

    function setUp() public {
        // Deploy implementations
        vaultImpl = new ProjectVault();
        governanceImpl = new GovernanceModule();
        disputesImpl = new DisputesModule();
        milestonesImpl = new MilestonesModule();

        // Deploy platform
        platform = new PlatformV2(
            address(vaultImpl),
            address(governanceImpl),
            address(disputesImpl),
            address(milestonesImpl)
        );
    }

    function testCreateProjectDeploysModules() public {
        MockProject project = new MockProject();

        uint256 id = platform.createProject(address(project));

        (
            address vault,
            address governance,
            address disputes,
            address creator,

        ) = platform.projects(id);

        assertTrue(vault != address(0));
        assertTrue(governance != address(0));
        assertTrue(disputes != address(0));
        assertEq(creator, address(this));
    }

    function testVaultInitializedCorrectly() public {
        MockProject project = new MockProject();

        uint256 projectId = platform.createProject(address(project));

        (address vaultAddr, , address disputesAddr, , ) = platform.projects(
            projectId
        );

        IProjectVault vault = IProjectVault(vaultAddr);

        // Initial state must be Locked (enum 0)
        assertEq(uint256(vault.state()), 0);

        // Guardian role must belong to disputes module
        bytes32 guardianRole = keccak256("GUARDIAN_ROLE");

        bool hasRole = ProjectVault(vaultAddr).hasRole(
            guardianRole,
            disputesAddr
        );

        assertTrue(hasRole);
    }

    function testMultipleProjectsAreIndependent() public {
        MockProject project1 = new MockProject();
        MockProject project2 = new MockProject();

        uint256 id1 = platform.createProject(address(project1));
        uint256 id2 = platform.createProject(address(project2));

        (address vault1, , , , ) = platform.projects(id1);
        (address vault2, , , , ) = platform.projects(id2);

        assertTrue(vault1 != vault2);
    }
}
