// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.30;

// import {Test} from "forge-std/Test.sol";
// import {PlatformV2} from "../../../src/contracts/v2/core/PlatformV2.sol";
// import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
// import {GovernanceModule} from "../../../src/contracts/v2/modules/GovernanceModule.sol";
// import {DisputesModule} from "../../../src/contracts/v2/modules/DisputesModule.sol";
// import {MilestonesModule} from "../../../src/contracts/v2/modules/MilestonesModule.sol";
// import {IGovernanceModule} from "../../../src/interfaces/v2/IGovernanceModule.sol";
// import {IProjectVault} from "../../../src/interfaces/v2/IProjectVault.sol";

// contract MockProject {}

// /**
//  * @title PlatformIsolationTest
//  * @notice Tests that projects are fully isolated from each other.
//  */
// contract PlatformIsolationTest is Test {
//     PlatformV2 platform;
//     ProjectVault vaultImpl;
//     GovernanceModule governanceImpl;
//     DisputesModule disputesImpl;
//     MilestonesModule milestonesImpl;

//     function setUp() public {
//         vaultImpl = new ProjectVault();
//         governanceImpl = new GovernanceModule();
//         disputesImpl = new DisputesModule();
//         milestonesImpl = new MilestonesModule();

//         platform = new PlatformV2(
//             address(vaultImpl),
//             address(governanceImpl),
//             address(disputesImpl),
//             address(milestonesImpl)
//         );
//     }

//     /**
//      * @notice Verifies that governance actions on one project don't affect others.
//      */
//     function testProjectsAreFullyIsolated() public {
//         MockProject p1 = new MockProject();
//         MockProject p2 = new MockProject();

//         uint256 id1 = platform.createProject(address(p1));
//         uint256 id2 = platform.createProject(address(p2));

//         (address v1, address g1, , , ) = platform.projects(id1);
//         (address v2, address g2, , , ) = platform.projects(id2);

//         assertTrue(v1 != v2);
//         assertTrue(g1 != g2);

//         IGovernanceModule gov1 = IGovernanceModule(g1);
//         IProjectVault vault1 = IProjectVault(v1);
//         IProjectVault vault2 = IProjectVault(v2);

//         uint256 proposalId = gov1.propose(
//             IGovernanceModule.Action.ActivateVault,
//             0
//         );

//         vm.prank(address(1));
//         gov1.vote(proposalId, IGovernanceModule.Vote.Yes);

//         vm.prank(address(2));
//         gov1.vote(proposalId, IGovernanceModule.Vote.Yes);

//         vm.warp(block.timestamp + 3 days + 1);
//         gov1.execute(proposalId);

//         assertEq(uint256(vault1.state()), 1);
//         assertEq(uint256(vault2.state()), 0);
//     }
// }
