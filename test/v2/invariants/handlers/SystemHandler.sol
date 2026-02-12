// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProjectVault} from "../../../../src/contracts/v2/core/ProjectVault.sol";
import {GovernanceModule} from "../../../../src/contracts/v2/modules/GovernanceModule.sol";
import {IGovernanceModule} from "../../../../src/interfaces/v2/IGovernanceModule.sol";
import {DisputesModule} from "../../../../src/contracts/v2/modules/DisputesModule.sol";
import {MockERC20} from "../../../../src/contracts/mocks/shared/MockERC20.sol";

/**
 * @title SystemHandler
 * @notice Handler for system invariants testing.
 *         Simulates user interactions with the vault, governance, and disputes modules.
 */
contract SystemHandler is Test {
    ProjectVault public vault;
    GovernanceModule public governance;
    DisputesModule public disputes;
    MockERC20 public token;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    uint256 public totalDeposited;
    uint256 public totalReleased;

    /**
     * @notice Constructor initializes the handler with references to the vault, governance, disputes modules, and the token.
     *         It also mints tokens for Alice and Bob to interact with the system.
     */
    constructor(
        ProjectVault _vault,
        GovernanceModule _gov,
        DisputesModule _disputes,
        MockERC20 _token
    ) {
        vault = _vault;
        governance = _gov;
        disputes = _disputes;
        token = _token;

        token.mint(alice, 1_000_000 ether);
        token.mint(bob, 1_000_000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            ACTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Simulates a deposit action by Alice. It checks if the vault is in the Locked state before attempting to deposit.
     */
    function deposit(uint256 amount) public {
        amount = bound(amount, 1 ether, 100 ether);

        if (vault.state() != ProjectVault.VaultState.Locked) return;

        vm.startPrank(alice);
        token.approve(address(vault), amount);

        try vault.deposit(address(token), amount) {
            totalDeposited += amount;
        } catch {}

        vm.stopPrank();
    }

    /**
     * @notice Simulates an activate action by Alice. It checks if the vault is in the Locked state before attempting to activate.
     */
    function activate() public {
        if (vault.state() != ProjectVault.VaultState.Locked) return;

        // 1. Crear propuesta
        vm.prank(alice);
        uint256 id = governance.propose(IGovernanceModule.Action.ActivateVault);

        // 2. Votar YES con mayoría
        vm.prank(alice);
        governance.vote(id, IGovernanceModule.Vote.Yes);

        vm.prank(bob);
        governance.vote(id, IGovernanceModule.Vote.Yes);

        // 3. Avanzar tiempo
        vm.warp(block.timestamp + governance.VOTING_PERIOD() + 1);

        // 4. Ejecutar
        try governance.execute(id) {} catch {}
    }

    /**
     * @notice Simulates a release action by the governance module. It checks if the vault is active and not paused before attempting to release funds.
     */
    function release(uint256 amount) public {
        amount = bound(amount, 1 ether, 50 ether);

        if (vault.paused()) return;
        if (vault.state() != ProjectVault.VaultState.Active) return;

        vm.prank(address(governance));

        try vault.release(address(token), alice, amount) {
            totalReleased += amount;
        } catch {}
    }

    /**
     * @notice Simulates opening a dispute by Alice. It checks if the vault is active before attempting to open a dispute.
     */
    function openDispute() public {
        if (vault.state() != ProjectVault.VaultState.Active) return;

        vm.prank(alice);
        try disputes.openDispute("Random dispute") {} catch {}
    }

    /**
     * @notice Simulates resolving a dispute by the disputes module. It checks if there are any disputes before attempting to resolve.
     */
    function resolveDispute(bool accepted) public {
        if (disputes.disputeCount() == 0) return;

        try disputes.resolveDispute(1, accepted) {} catch {}
    }
}
