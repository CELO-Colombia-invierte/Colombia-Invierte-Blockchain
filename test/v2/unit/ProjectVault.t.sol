// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";

contract ProjectVaultTest is Test {
    ProjectVault vault;

    address project = address(0xA);
    address governance = address(0xB);
    address guardian = address(0xC);

    function setUp() public {
        vault = new ProjectVault();
        vault.initialize(project, governance, guardian);
    }

    function testInitializeSetsStateAndRoles() public view {
        assertEq(uint256(vault.state()), 0);
        assertEq(vault.project(), project);

        assertTrue(vault.hasRole(vault.GOVERNANCE_ROLE(), governance));
        assertTrue(vault.hasRole(vault.GUARDIAN_ROLE(), guardian));
        assertTrue(vault.hasRole(vault.CONTROLLER_ROLE(), project));
    }

    function testInitializeCannotBeCalledTwice() public {
        vm.expectRevert();
        vault.initialize(project, governance, guardian);
    }

    function testActivateOnlyGovernance() public {
        vm.prank(governance);
        vault.activate();

        assertEq(uint256(vault.state()), 1);
    }

    function testCloseOnlyGovernance() public {
        vm.prank(governance);
        vault.activate();

        vm.prank(governance);
        vault.close();

        assertEq(uint256(vault.state()), 2);
    }

    function testReleaseRevertsIfNotActive() public {
        vm.prank(governance);
        vm.expectRevert();
        vault.release(address(1), address(2), 1 ether);
    }
}
