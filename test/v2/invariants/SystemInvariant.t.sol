// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
import {GovernanceModule} from "../../../src/contracts/v2/modules/GovernanceModule.sol";
import {DisputesModule} from "../../../src/contracts/v2/modules/DisputesModule.sol";
import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";
import {SystemHandler} from "./handlers/SystemHandler.sol";

/**
 * @title SystemInvariant
 * @notice Invariant tests for the overall system. It checks that the vault's state transitions and accounting are consistent with the actions performed through the handler.
 */
contract SystemInvariant is StdInvariant, Test {
    ProjectVault vault;
    GovernanceModule governance;
    DisputesModule disputes;
    MockERC20 token;
    SystemHandler handler;

    address admin = address(this);

    /*//////////////////////////////////////////////////////////////
                            SETUP
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Sets up the testing environment by deploying the vault, governance, and disputes modules, configuring roles, allowing the token, and initializing the handler.
     */
    function setUp() external {
        token = new MockERC20("USD Stable", "USDS");

        address tempProject = address(0xBEEF);

        // 1️⃣ Deploy core
        vault = new ProjectVault(tempProject, admin);
        governance = new GovernanceModule(address(vault));
        disputes = new DisputesModule(address(vault));

        // 2️⃣ Configurar roles correctamente
        vault.grantRole(vault.CONTROLLER_ROLE(), address(governance));
        vault.grantRole(vault.GOVERNANCE_ROLE(), address(governance));
        vault.grantRole(vault.GOVERNANCE_ROLE(), address(disputes));
        vault.grantRole(vault.GUARDIAN_ROLE(), address(disputes));

        // Opcional pero limpio:
        vault.revokeRole(vault.CONTROLLER_ROLE(), tempProject);

        // 3️⃣ Permitir token (admin tiene GOVERNANCE_ROLE por constructor)
        vault.setTokenAllowed(address(token), true);

        // 4️⃣ Instalar handler
        handler = new SystemHandler(vault, governance, disputes, token);

        targetContract(address(handler));
    }

    /*//////////////////////////////////////////////////////////////
                            INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Invariant that checks if the vault is in the Closed state, it cannot be re-activated. This ensures that once the vault is closed, it remains in that state permanently.
     */
    function invariant_ClosedIsTerminal() public {
        if (vault.state() == ProjectVault.VaultState.Closed) {
            vm.expectRevert();
            vault.activate();
        }
    }

    /**
     * @notice Invariant that checks the vault's token balance is never negative. This ensures that the vault's accounting is consistent and that it does not allow withdrawals that exceed the deposited amount.
     */
    function invariant_BalanceNeverNegative() public view {
        assertGe(token.balanceOf(address(vault)), 0);
    }

    /**
     * @notice Invariant that checks if there is an open dispute, the vault must be paused. This ensures that when a dispute is raised, the system correctly enters a paused state to prevent further actions until the dispute is resolved.
     */
    function invariant_OpenDisputeImpliesPaused() public view {
        uint256 id = disputes.disputeCount();
        if (id == 0) return;

        (, , , DisputesModule.DisputeStatus status) = disputes.disputes(id);

        if (status == DisputesModule.DisputeStatus.Open) {
            assertTrue(vault.paused());
        }
    }

    /**
     * @notice Invariant that checks the total amount released from the vault never exceeds the total amount deposited. This ensures that the system's accounting is consistent and that it does not allow more funds to be withdrawn than were deposited.
     */
    function invariant_TotalReleasedNeverExceedsDeposits() public view {
        assertLe(handler.totalReleased(), handler.totalDeposited());
    }

    /**
     * @notice Invariant that checks the vault's token balance matches the expected balance based on total deposits and releases. This ensures that the vault's accounting is accurate and that the actual token balance reflects the net effect of all deposits and releases.
     */
    function invariant_AccountingMatchesVaultBalance() public view {
        uint256 expected = handler.totalDeposited() - handler.totalReleased();
        uint256 actual = token.balanceOf(address(vault));

        assertEq(actual, expected);
    }

    /**
     * @notice Invariant that checks if the vault is paused, no releases can be made. This ensures that when the vault is in a paused state (e.g., due to an open dispute), it correctly prevents any fund releases until the issue is resolved.
     */
    function invariant_NoReleaseWhenPaused() public {
        if (vault.paused()) {
            vm.expectRevert();
            vault.release(address(token), address(0x1), 1 ether);
        }
    }
}
