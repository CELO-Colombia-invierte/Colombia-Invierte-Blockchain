// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {GovernanceModule} from "../../../src/contracts/v2/modules/GovernanceModule.sol";
import {IGovernanceModule} from "../../../src/interfaces/v2/IGovernanceModule.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";

contract GovernanceModuleTest is Test {
    GovernanceModule gov;
    ProjectVault vault;

    function setUp() public {
        vault = new ProjectVault();

        gov = new GovernanceModule();

        vault.initialize(address(1), address(gov), address(2));

        gov.initialize(address(vault));
    }

    function testInitializeSetsVault() public view {
        assertEq(gov.vault(), address(vault));
    }

    function testCannotInitializeTwice() public {
        vm.expectRevert();
        gov.initialize(address(vault));
    }

    function testProposalLifecycle() public {
        uint256 id = gov.propose(IGovernanceModule.Action.ActivateVault);

        vm.prank(address(1));
        gov.vote(id, IGovernanceModule.Vote.Yes);

        vm.prank(address(2));
        gov.vote(id, IGovernanceModule.Vote.Yes);

        vm.warp(block.timestamp + 3 days + 1);

        gov.execute(id);

        (, , , , bool executed) = gov.proposals(id);
        assertTrue(executed);
    }
}
