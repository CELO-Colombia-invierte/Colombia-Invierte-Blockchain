// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";

/**
 * @title ProjectVaultPausableTest
 * @notice Tests pause/unpause functionality and access control.
 */
contract ProjectVaultPausableTest is Test {
    ProjectVault vault;

    address project = address(0xA);
    address governance = address(0xB);
    address guardian = address(0xC);

    function setUp() public {
        vault = new ProjectVault();
        vault.initialize(project, governance, guardian);
    }

    /**
     * @notice Tests that guardian can pause the vault.
     */
    function testGuardianCanPause() public {
        vm.prank(guardian);
        vault.pause();

        assertTrue(vault.paused());
    }

    /**
     * @notice Tests that governance can unpause the vault.
     */
    function testGovernanceCanUnpause() public {
        vm.prank(guardian);
        vault.pause();

        vm.prank(governance);
        vault.unpause();

        assertFalse(vault.paused());
    }

    /**
     * @notice Tests that non-guardian cannot pause.
     */
    function testNonGuardianCannotPause() public {
        vm.expectRevert();
        vault.pause();
    }
}
