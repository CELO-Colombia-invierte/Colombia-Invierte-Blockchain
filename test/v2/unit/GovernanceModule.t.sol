// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {GovernanceModule} from "../../../src/contracts/v2/modules/GovernanceModule.sol";
import {IGovernanceModule} from "../../../src/interfaces/v2/IGovernanceModule.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
import {MilestonesModule} from "../../../src/contracts/v2/modules/MilestonesModule.sol";

/**
 * @title GovernanceModuleTest
 * @notice Unit tests for GovernanceModule proposal and voting mechanics.
 */
contract GovernanceModuleTest is Test {
    GovernanceModule gov;
    ProjectVault vault;
    MilestonesModule milestones;

    function setUp() public {
        vault = new ProjectVault();
        milestones = new MilestonesModule();

        gov = new GovernanceModule();

        vault.initialize(address(1), address(gov), address(2));

        gov.initialize(address(vault), address(milestones));
    }

    /**
     * @notice Tests that initialize correctly sets the vault address.
     */
    function testInitializeSetsVault() public view {
        assertEq(gov.vault(), address(vault));
    }

    /**
     * @notice Tests that initialize cannot be called twice.
     */
    function testCannotInitializeTwice() public {
        vm.expectRevert();
        gov.initialize(address(vault), address(milestones));
    }

    /**
     * @notice Tests full proposal lifecycle: propose, vote, execute.
     */
    function testProposalLifecycle() public {
        uint256 id = gov.propose(IGovernanceModule.Action.ActivateVault, 0);

        vm.prank(address(1));
        gov.vote(id, IGovernanceModule.Vote.Yes);

        vm.prank(address(2));
        gov.vote(id, IGovernanceModule.Vote.Yes);

        vm.warp(block.timestamp + 3 days + 1);

        gov.execute(id);

        (, , , , , bool executed) = gov.proposals(id);
        assertTrue(executed);
    }
}
