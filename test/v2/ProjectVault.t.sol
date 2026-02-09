// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProjectVault} from "../../src/contracts/v2/core/ProjectVault.sol";
import {MockERC20} from "../../src/contracts/mocks/shared/MockERC20.sol";

/**
 * @title ProjectVaultTest
 * @notice Tests for the ProjectVault contract.
 */
contract ProjectVaultTest is Test {
    /// @dev The vault instance used for testing.
    ProjectVault vault;
    /// @dev A mock ERC20 token used for testing deposits and releases.
    MockERC20 token;
    /// @dev The admin address with permissions to manage the vault.
    address admin = address(0xA11CE);
    /// @dev The project address that owns the vault.
    address project = address(0xBEEF);
    /// @dev A user address that will interact with the vault.
    address user = address(0xCAFE);

    function setUp() external {
        token = new MockERC20("USD Stable", "USDS");
        vault = new ProjectVault(project, admin);

        vm.prank(admin);
        vault.setTokenAllowed(address(token), true);

        token.mint(user, 1_000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Tests that deposits can only be made when the vault is locked.
     */
    function testDepositOnlyWhenLocked() external {
        vm.prank(user);
        token.approve(address(vault), 100 ether);

        vm.prank(user);
        vault.deposit(address(token), 100 ether);

        assertEq(token.balanceOf(address(vault)), 100 ether);
    }

    /**
     * @notice Tests that deposits cannot be made when the vault is active.
     */
    function testCannotDepositWhenActive() external {
        vm.prank(project);
        vault.activate();

        vm.expectRevert(ProjectVault.InvalidState.selector);
        vm.prank(user);
        vault.deposit(address(token), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            RELEASE
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Tests that only the project can release funds from the vault.
     */
    function testOnlyGovernanceCanRelease() external {
        vm.prank(project);
        vault.activate();

        vm.expectRevert();
        vm.prank(user);
        vault.release(address(token), user, 1 ether);
    }

    /**
     * @notice Tests that funds can be released from the vault when it is active.
     */
    function testReleaseTransfersFunds() external {
        vm.prank(user);
        token.approve(address(vault), 100 ether);

        vm.prank(user);
        vault.deposit(address(token), 100 ether);

        vm.prank(project);
        vault.activate();

        vm.prank(admin);
        vault.release(address(token), user, 40 ether);

        assertEq(token.balanceOf(user), 940 ether);
    }
}
