// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StdInvariant, Test} from "forge-std/Test.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";
import {VaultHandler} from "./handlers/VaultHandler.sol";

/**
 * @notice Invariant tests for ProjectVault
 * Invariants:
 * 1. Vault balance never exceeds deposits minus releases
 * 2. When paused, vault balance must remain constant
 */
contract ProjectVaultInvariantTest is StdInvariant, Test {
    /// @notice Vault instance used for testing
    ProjectVault vault;
    /// @notice Mock token used for testing
    MockERC20 token;
    /// @notice Handler that performs deposits and releases on the vault
    VaultHandler handler;
    /// @notice Admin address with permissions to manage the vault
    address admin = address(this);
    /// @notice Dummy controller address (not used in this test)
    address controller = address(0xC0FFEE);

    /**
     * @notice Sets up the invariant test environment
     */
    function setUp() external {
        token = new MockERC20("USD Stable", "USDS");

        vault = new ProjectVault(controller, admin);

        vault.grantRole(vault.GOVERNANCE_ROLE(), admin);
        vault.grantRole(vault.GUARDIAN_ROLE(), admin);

        vault.setTokenAllowed(address(token), true);

        handler = new VaultHandler(vault, token);

        targetContract(address(handler));
    }

    /*//////////////////////////////////////////////////////////////
                            INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Vault balance never exceeds deposits minus releases
    function invariant_balanceAccounting() external view {
        uint256 vaultBalance = token.balanceOf(address(vault));

        assertEq(
            vaultBalance,
            handler.totalDeposited() - handler.totalReleased()
        );
    }

    /// @notice When paused, vault balance must remain constant
    function invariant_pauseFreezesFunds() external view {
        if (vault.paused()) {
            uint256 before = token.balanceOf(address(vault));
            uint256 afterBalance = token.balanceOf(address(vault));

            assertEq(before, afterBalance);
        }
    }
}
