// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProjectVault} from "../../src/contracts/v2/core/ProjectVault.sol";
import {DisputesModule} from "../../src/contracts/v2/modules/DisputesModule.sol";
import {IProjectVault} from "../../src/interfaces/v2/IProjectVault.sol";

/**
 * @title DisputesModuleTest
 * @notice Test contract for the DisputesModule of the Colombia Invierte platform.
 *         This contract sets up a testing environment with a ProjectVault and a DisputesModule to validate their interactions.
 */
contract DisputesModuleTest is Test {
    /// @notice Instance of the ProjectVault used for testing.
    ProjectVault vault;
    /// @notice Instance of the DisputesModule used for testing.
    DisputesModule disputes;
    /// @notice Address representing the admin user in tests.
    address admin = address(this);
    /// @notice Address representing a regular user (Alice) in tests.
    address alice = address(0xA11CE);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Sets up the testing environment by deploying a ProjectVault and a DisputesModule, granting necessary permissions, and activating the vault.
     */
    function setUp() external {
        vault = new ProjectVault(address(0xDEAD), admin);
        disputes = new DisputesModule(address(vault));

        vault.grantRole(vault.GUARDIAN_ROLE(), address(disputes));
        vault.grantRole(vault.GOVERNANCE_ROLE(), admin);

        vault.grantRole(vault.GOVERNANCE_ROLE(), address(disputes));

        vm.prank(address(0xDEAD));
        vault.activate();
    }

    /*//////////////////////////////////////////////////////////////
                                TESTS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Tests that a user can successfully open a dispute when the vault is active, and that the dispute details are correctly stored.
     */
    function testOpenDisputeWhenActive() external {
        vm.prank(alice);
        uint256 id = disputes.openDispute("Fraud suspicion");

        assertEq(id, 1);

        (address opener, , , DisputesModule.DisputeStatus status) = disputes
            .disputes(id);

        assertEq(opener, alice);
        assertEq(uint256(status), uint256(DisputesModule.DisputeStatus.Open));

        assertTrue(vault.paused());
    }

    /**
     * @notice Tests that a user cannot open a dispute when the vault is not active, and that the appropriate error is reverted.
     */
    function testCannotOpenDisputeWhenNotActive() external {
        vault.close();

        vm.prank(alice);
        vm.expectRevert(DisputesModule.NotActiveVault.selector);
        disputes.openDispute("Test");
    }

    /**
     * @notice Tests that an authorized user can resolve a dispute as accepted, and that this action correctly updates the dispute status and closes the vault.
     */
    function testResolveAcceptedClosesVault() external {
        vm.prank(alice);
        uint256 id = disputes.openDispute("Issue");

        disputes.resolveDispute(id, true);

        assertEq(
            uint256(vault.state()),
            uint256(IProjectVault.VaultState.Closed)
        );
    }

    /**
     * @notice Tests that an authorized user can resolve a dispute as rejected, and that this action correctly updates the dispute status and unpauses the vault.
     */
    function testResolveRejectedUnpausesVault() external {
        vm.prank(alice);
        uint256 id = disputes.openDispute("Minor issue");

        disputes.resolveDispute(id, false);

        assertFalse(vault.paused());
    }

    /**
     * @notice Tests that a dispute cannot be resolved twice, and that the appropriate error is reverted when trying to resolve an already resolved dispute.
     */
    function testCannotResolveTwice() external {
        vm.prank(alice);
        uint256 id = disputes.openDispute("Test");

        disputes.resolveDispute(id, true);

        vm.expectRevert(DisputesModule.AlreadyResolved.selector);
        disputes.resolveDispute(id, false);
    }

    /**
     * @notice Tests that a dispute cannot be resolved by an unauthorized user, and that the appropriate error is reverted when trying to resolve a dispute without permissions.
     */
    function testInvalidDispute() external {
        vm.expectRevert(DisputesModule.InvalidDispute.selector);
        disputes.resolveDispute(999, true);
    }

    /**
     * @notice Tests that a dispute cannot be resolved by an unauthorized user, and that the appropriate error is reverted when trying to resolve a dispute without permissions.
     */
    function testOnlyGovernanceCanResolve() external {
        vm.prank(alice);
        uint256 id = disputes.openDispute("Test");

        vm.prank(alice);
        vm.expectRevert(DisputesModule.Unauthorized.selector);
        disputes.resolveDispute(id, true);
    }
}
