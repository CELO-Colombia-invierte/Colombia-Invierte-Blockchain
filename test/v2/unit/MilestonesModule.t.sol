// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.30;

// import {Test} from "forge-std/Test.sol";
// import {MilestonesModule} from "../../../src/contracts/v2/modules/MilestonesModule.sol";
// import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
// import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";

// /**
//  * @title MilestonesModuleTest
//  * @notice Unit tests for MilestonesModule milestone lifecycle.
//  */
// contract MilestonesModuleTest is Test {
//     MilestonesModule milestones;
//     ProjectVault vault;
//     MockERC20 token;

//     function setUp() public {
//         vault = new ProjectVault();
//         milestones = new MilestonesModule();

//         vault.initialize(address(1), address(milestones), address(2));
//         milestones.initialize(address(vault), address(this));
//         vault.grantRole(vault.GOVERNANCE_ROLE(), address(this));
//         vault.activate();

//         token = new MockERC20("Mock", "MOCK");
//         token.mint(address(this), 1_000_000 ether);

//         vm.prank(address(2));
//         vault.setTokenAllowed(address(token), true);
//     }

//     /**
//      * @notice Tests full milestone flow: propose, approve, execute.
//      */
//     function testProposeApproveExecute() public {
//         bool success = token.transfer(address(vault), 100 ether);
//         require(success);

//         uint256 id = milestones.proposeMilestone(
//             "Phase 1",
//             address(token),
//             address(3),
//             50 ether
//         );

//         milestones.approveMilestone(id);
//         milestones.executeMilestone(id);

//         assertEq(token.balanceOf(address(3)), 50 ether);
//     }
// }
