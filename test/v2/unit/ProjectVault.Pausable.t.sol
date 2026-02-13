// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";

contract ProjectVaultPausableTest is Test {
    ProjectVault vault;

    address project = address(0xA);
    address governance = address(0xB);
    address guardian = address(0xC);

    function setUp() public {
        vault = new ProjectVault();
        vault.initialize(project, governance, guardian);
    }

    function testGuardianCanPause() public {
        vm.prank(guardian);
        vault.pause();

        assertTrue(vault.paused());
    }

    function testGovernanceCanUnpause() public {
        vm.prank(guardian);
        vault.pause();

        vm.prank(governance);
        vault.unpause();

        assertFalse(vault.paused());
    }

    function testNonGuardianCannotPause() public {
        vm.expectRevert();
        vault.pause();
    }
}
