// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
import {GovernanceModule} from "../../../src/contracts/v2/modules/GovernanceModule.sol";
import {IGovernanceModule} from "../../../src/interfaces/v2/IGovernanceModule.sol";
import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";

/**
 * @notice Test suite for the governance flow of the ProjectVault, covering proposal creation, voting, and execution of vault state changes.
 */
contract GovernanceVaultFlowTest is Test {
    /// @notice The ProjectVault instance being tested
    ProjectVault vault;
    /// @notice The GovernanceModule instance used to control the vault
    GovernanceModule gov;
    /// @notice Mock ERC20 token used for testing deposits
    MockERC20 token;
    /// @notice Test addresses representing different users
    address admin = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    /*//////////////////////////////////////////////////////////////
                            SETUP
//////////////////////////////////////////////////////////////*/
    /**
     * @notice Sets up the test environment before each test case.
     * @dev Deploys the vault and mock token, grants roles, and funds the vault.
     */
    function setUp() external {
        token = new MockERC20("USD Stable", "USDS");

        vault = new ProjectVault(
            address(0xDEAD), // project (dummy)
            admin
        );

        gov = new GovernanceModule(address(vault));

        //  Governance is the authority
        vault.grantRole(vault.CONTROLLER_ROLE(), address(gov));
        vault.grantRole(vault.GOVERNANCE_ROLE(), address(gov));
        vault.grantRole(vault.GUARDIAN_ROLE(), address(gov));

        vault.setTokenAllowed(address(token), true);
    }

    /**
     * @notice Helper function to create and pass a governance proposal for a specific action.
     * @param action The governance action to propose and execute.
     */
    function _passProposal(
        IGovernanceModule.Action action
    ) internal returns (uint256 id) {
        id = gov.propose(action);

        vm.prank(alice);
        gov.vote(id, IGovernanceModule.Vote.Yes);

        vm.prank(bob);
        gov.vote(id, IGovernanceModule.Vote.Yes);

        vm.warp(block.timestamp + gov.VOTING_PERIOD() + 1);
        gov.execute(id);
    }

    /**
     * @notice Tests that a proposal to activate the vault can be successfully created, voted on, and executed, resulting in the vault's state changing to Active.
     */
    function testActivateVaultViaGovernance() external {
        _passProposal(IGovernanceModule.Action.ActivateVault);

        assertEq(
            uint256(vault.state()),
            uint256(ProjectVault.VaultState.Active)
        );
    }

    /*
     * @notice Tests that voting on a proposal is not allowed after the voting period has ended.
     */
    function testFreezeVaultViaGovernance() external {
        // Primero activamos el vault
        _passProposal(IGovernanceModule.Action.ActivateVault);
        assertEq(
            uint256(vault.state()),
            uint256(ProjectVault.VaultState.Active)
        );

        // Freeze
        _passProposal(IGovernanceModule.Action.FreezeVault);

        // Deposit debe fallar
        token.mint(alice, 10 ether);
        vm.startPrank(alice);
        token.approve(address(vault), 10 ether);

        vm.expectRevert(); // Pausable enforced
        vault.deposit(address(token), 1 ether);
        vm.stopPrank();
    }

    /*
     * @notice Tests that a proposal to unfreeze the vault can be successfully created, voted on, and executed, allowing deposits and releases to function again.
     */
    function testUnfreezeVaultViaGovernance() external {
        _passProposal(IGovernanceModule.Action.ActivateVault);
        _passProposal(IGovernanceModule.Action.FreezeVault);
        _passProposal(IGovernanceModule.Action.UnfreezeVault);

        // Vault sigue en Active
        assertEq(
            uint256(vault.state()),
            uint256(ProjectVault.VaultState.Active)
        );

        // deposit sigue prohibido (porque no está Locked)
        token.mint(alice, 10 ether);
        vm.startPrank(alice);
        token.approve(address(vault), 10 ether);

        vm.expectRevert(ProjectVault.VaultClosed.selector);
        vault.deposit(address(token), 1 ether);

        vm.stopPrank();

        // release vuelve a estar permitido
        vm.prank(address(gov));
    }

    /*
     * @notice Tests that a proposal to close the vault can be successfully created, voted on, and executed, resulting in the vault's state changing to Closed and blocking further deposits and releases.
     */
    function testCloseVaultViaGovernance() external {
        // Activate
        _passProposal(IGovernanceModule.Action.ActivateVault);

        // Close
        _passProposal(IGovernanceModule.Action.CloseVault);

        assertEq(
            uint256(vault.state()),
            uint256(ProjectVault.VaultState.Closed)
        );

        // Deposit bloqueado
        token.mint(alice, 10 ether);
        vm.startPrank(alice);
        token.approve(address(vault), 10 ether);

        vm.expectRevert(ProjectVault.VaultClosed.selector);
        vault.deposit(address(token), 1 ether);
        vm.stopPrank();

        // Release bloqueado
        vm.prank(address(gov));
        vm.expectRevert(ProjectVault.VaultNotActive.selector);
        vault.release(address(token), alice, 1 ether);
    }

    /**
     * @notice Tests that voting on a proposal is not allowed after the voting period has ended.
     */

    function testCannotExecuteProposalTwice() external {
        uint256 id = gov.propose(IGovernanceModule.Action.ActivateVault);

        vm.prank(alice);
        gov.vote(id, IGovernanceModule.Vote.Yes);

        vm.prank(bob);
        gov.vote(id, IGovernanceModule.Vote.Yes);

        vm.warp(block.timestamp + gov.VOTING_PERIOD() + 1);
        gov.execute(id);

        vm.expectRevert(GovernanceModule.AlreadyExecuted.selector);
        gov.execute(id);
    }

    /**
     * @notice Tests that a proposal cannot be executed if it does not have enough yes votes to reach quorum.
     */
    function testCannotExecuteWithoutQuorum() external {
        uint256 id = gov.propose(IGovernanceModule.Action.ActivateVault);

        vm.prank(alice);
        gov.vote(id, IGovernanceModule.Vote.Yes);

        vm.prank(bob);
        gov.vote(id, IGovernanceModule.Vote.No);

        vm.warp(block.timestamp + gov.VOTING_PERIOD() + 1);

        vm.expectRevert(GovernanceModule.QuorumNotReached.selector);
        gov.execute(id);
    }
}
