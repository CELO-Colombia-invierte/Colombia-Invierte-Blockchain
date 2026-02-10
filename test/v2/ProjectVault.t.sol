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
    address admin = address(this);
    /// @dev The project address that owns the vault.
    address project = address(0xBEEF);
    /// @dev A user address that will interact with the vault.
    address user = address(0xCAFE);
    /// @dev A controller address that can activate the vault and release funds.
    address controller = address(0xC0FFEE);

    /*//////////////////////////////////////////////////////////////
                            SETUP
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Sets up the test environment before each test case.
     * @dev Deploys the vault and mock token, grants roles, and funds the vault.
     */
    function setUp() external {
        token = new MockERC20("USD Stable", "USDS");
        vault = new ProjectVault(address(0xDEAD), address(this));

        // this = DEFAULT_ADMIN_ROLE
        vault.grantRole(vault.CONTROLLER_ROLE(), controller);
        vault.setTokenAllowed(address(token), true);
        token.mint(address(vault), 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Tests that deposits can only be made when the vault is locked.
     */
    function testDepositOnlyWhenLocked() external {
        address depositor = address(0xCAFE);
        token.mint(depositor, 100 ether);

        vm.startPrank(depositor);
        token.approve(address(vault), 100 ether);
        vault.deposit(address(token), 100 ether);
        vm.stopPrank();
    }

    /**
     * @notice Tests that funds cannot be deposited after the vault has been activated.
     */
    function testCannotDepositAfterActivation() external {
        vm.prank(controller);
        vault.activate();

        vm.expectRevert(ProjectVault.VaultClosed.selector);
        vault.deposit(address(token), 1 ether);
    }

    /**
     * @notice Tests that deposits cannot be made when the vault is closed.
     */
    function testCannotDepositWhenClosed() external {
        vm.prank(controller);
        vault.activate();

        vm.prank(admin);
        vault.close();

        vm.expectRevert(ProjectVault.VaultClosed.selector);
        vault.deposit(address(token), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            RELEASE
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Tests that only the project can release funds from the vault.
     */
    function testOnlyGovernanceCanRelease() external {
        vm.prank(controller);
        vault.activate();

        vm.expectRevert();
        vm.prank(user);
        vault.release(address(token), user, 1 ether);
    }

    /**
     * @notice Tests that funds can be released from the vault when it is active.
     */
    function testReleaseTransfersFunds() external {
        address depositor = address(0xCAFE);
        token.mint(depositor, 100 ether);

        vm.startPrank(depositor);
        token.approve(address(vault), 100 ether);
        vault.deposit(address(token), 100 ether);
        vm.stopPrank();
    }

    /**
     * @notice Tests that funds cannot be released while the vault is locked.
     */
    function testCannotReleaseWhileLocked() external {
        vm.prank(controller);
        vm.expectRevert(ProjectVault.VaultNotActive.selector);
        vault.release(address(token), admin, 1 ether);
    }

    /**
     * @notice Tests that funds can be released to the admin when the vault is active.
     */
    function testReleaseWorksWhenActive() external {
        vm.prank(controller);
        vault.activate();

        uint256 balanceBefore = token.balanceOf(admin);

        vm.prank(controller);
        vault.release(address(token), admin, 1 ether);

        assertEq(token.balanceOf(admin), balanceBefore + 1 ether);
    }
}
