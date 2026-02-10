// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProjectVault} from "../../src/contracts/v2/core/ProjectVault.sol";
import {MockERC20} from "../../src/contracts/mocks/shared/MockERC20.sol";

/**
 * @title ProjectVaultPausableTest
 * @notice Tests for the pausable functionality of the ProjectVault contract.
 */

contract ProjectVaultPausableTest is Test {
    /// @dev The vault instance used for testing.
    ProjectVault vault;
    /// @dev A mock ERC20 token used for testing deposits and releases.
    MockERC20 token;
    /// @dev The admin address with permissions to manage the vault.
    address admin = address(this);
    /// @dev A controller address that can activate the vault and release funds.
    address controller = address(0xC0FFEE);
    /// @dev The guardian address that can pause and unpause the vault.
    address guardian = address(this); // by constructor
    /// @dev A user address that will interact with the vault.
    address user = address(0xCAFE);
    /// @dev The error signature for the enforced pause revert.
    bytes4 constant ENFORCED_PAUSE = bytes4(keccak256("EnforcedPause()"));

    /*//////////////////////////////////////////////////////////////
                            SETUP
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Sets up the test environment before each test case.
     * @dev Deploys the vault and mock token, grants roles, and funds the vault.
     */
    function setUp() external {
        token = new MockERC20("USD Stable", "USDS");
        vault = new ProjectVault(address(0xDEAD), admin);

        vault.grantRole(vault.CONTROLLER_ROLE(), controller);
        vault.setTokenAllowed(address(token), true);

        token.mint(user, 100 ether);
        token.mint(address(vault), 50 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            Core pausable tests
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Tests that deposits cannot be made when the vault is paused.
     */
    function testDepositFailsWhenPaused() external {
        vm.prank(guardian);
        vault.pause();

        vm.startPrank(user);
        token.approve(address(vault), 10 ether);

        vm.expectRevert(ENFORCED_PAUSE);
        vault.deposit(address(token), 10 ether);

        vm.stopPrank();
    }

    /**
     * @notice Tests that releases cannot be made when the vault is paused.
     */
    function testReleaseFailsWhenPaused() external {
        vm.prank(controller);
        vault.activate();

        vm.prank(guardian);
        vault.pause();

        vm.expectRevert(ENFORCED_PAUSE);
        vm.prank(controller);
        vault.release(address(token), admin, 1 ether);
    }

    /*
     * @notice Tests that unpausing the vault restores deposit and release functionality.
     */
    function testUnpauseRestoresDeposit() external {
        vm.prank(guardian);
        vault.pause();

        vm.prank(admin);
        vault.unpause();

        vm.startPrank(user);
        token.approve(address(vault), 5 ether);
        vault.deposit(address(token), 5 ether);
        vm.stopPrank();
    }

    /*
     * @notice Tests that unpausing the vault restores release functionality.
     */
    function testOnlyGuardianCanPause() external {
        vm.expectRevert();
        vm.prank(user);
        vault.pause();
    }

    /*
     * @notice Tests that only the guardian can unpause the vault.
     */
    function testOnlyGovernanceCanUnpause() external {
        vm.prank(guardian);
        vault.pause();

        vm.expectRevert();
        vm.prank(user);
        vault.unpause();
    }
}
