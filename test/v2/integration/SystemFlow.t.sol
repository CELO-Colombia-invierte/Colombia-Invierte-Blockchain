// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
import {GovernanceModule} from "../../../src/contracts/v2/modules/GovernanceModule.sol";
import {DisputesModule} from "../../../src/contracts/v2/modules/DisputesModule.sol";
import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";
import {IProjectVault} from "../../../src/interfaces/v2/IProjectVault.sol";
import {IGovernanceModule} from "../../../src/interfaces/v2/IGovernanceModule.sol";

/**
 * @notice This test simulates a full system flow, covering the main interactions between the ProjectVault, GovernanceModule, and DisputesModule. It ensures that the modules work together as expected in various scenarios, including dispute resolution outcomes.
 */
contract SystemFlowTest is Test {
    /*//////////////////////////////////////////////////////////////
                                VARIABLES    
    //////////////////////////////////////////////////////////////*/
    /// @notice Core vault contract
    ProjectVault vault;
    /// @notice Governance module
    GovernanceModule governance;
    /// @notice Disputes module
    DisputesModule disputes;
    /// @notice Mock ERC20 token used for testing
    MockERC20 token;

    /// @notice Test addresses
    address admin = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    /// @notice Deposit amount for testing
    uint256 constant DEPOSIT_AMOUNT = 100 ether;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Sets up the testing environment by deploying the core vault and modules, configuring permissions, allowing the test token, and funding the test user. This function is called before each test to ensure a clean state.
     */
    function setUp() external {
        token = new MockERC20("USD Stable", "USDS");

        // Deploy core vault
        vault = new ProjectVault(address(0xDEAD), admin);

        // Deploy modules
        governance = new GovernanceModule(address(vault));
        disputes = new DisputesModule(address(vault));

        // Governance permissions
        vault.grantRole(vault.CONTROLLER_ROLE(), address(governance));
        vault.grantRole(vault.GOVERNANCE_ROLE(), address(governance));
        vault.grantRole(vault.GUARDIAN_ROLE(), address(governance));

        // Disputes permissions
        vault.grantRole(vault.GUARDIAN_ROLE(), address(disputes));
        vault.grantRole(vault.GOVERNANCE_ROLE(), address(disputes));

        // Allow token
        vault.setTokenAllowed(address(token), true);

        // Fund user
        token.mint(alice, DEPOSIT_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                        FULL SYSTEM FLOW
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Tests a full system flow where a user deposits funds, the vault is activated via governance, a dispute is opened and accepted, leading to the vault being closed. It also verifies that funds cannot be released after closure.
     */
    function testFullFlow_DisputeAccepted_ClosesVault() external {
        uint256 aliceInitial = token.balanceOf(alice);

        // 1️⃣ Deposit while Locked
        vm.startPrank(alice);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(address(token), DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), aliceInitial - DEPOSIT_AMOUNT);
        assertEq(token.balanceOf(address(vault)), DEPOSIT_AMOUNT);

        // 2️⃣ Governance activates vault
        _passGovernanceProposal(IGovernanceModule.Action.ActivateVault);

        assertEq(
            uint256(vault.state()),
            uint256(IProjectVault.VaultState.Active)
        );

        uint256 releaseAmount = 20 ether;

        uint256 vaultBeforeRelease = token.balanceOf(address(vault));
        uint256 aliceBeforeRelease = token.balanceOf(alice);

        // release via governance
        vault.grantRole(vault.CONTROLLER_ROLE(), address(this));
        vault.release(address(token), alice, releaseAmount);

        assertEq(
            token.balanceOf(address(vault)),
            vaultBeforeRelease - releaseAmount
        );

        assertEq(token.balanceOf(alice), aliceBeforeRelease + releaseAmount);

        // 3️⃣ Alice opens dispute
        vm.prank(alice);
        uint256 disputeId = disputes.openDispute("Fraud suspicion");

        assertTrue(vault.paused());

        // 4️⃣ Governance resolves dispute (accepted → close)
        disputes.resolveDispute(disputeId, true);

        assertEq(
            uint256(vault.state()),
            uint256(IProjectVault.VaultState.Closed)
        );

        // 5️⃣ Ensure funds cannot be released anymore
        vm.expectRevert();
        vault.release(address(token), alice, 10 ether);
    }

    /**
     * @notice Tests a full system flow where a user deposits funds, the vault is activated via governance, a dispute is opened and rejected, leading to the vault being unpaused and remaining active.
     */
    function testFullFlow_DisputeRejected_UnpausesVault() external {
        // Deposit
        vm.startPrank(alice);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(address(token), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Activate via governance
        _passGovernanceProposal(IGovernanceModule.Action.ActivateVault);

        // Open dispute
        vm.prank(alice);
        uint256 disputeId = disputes.openDispute("Minor issue");

        assertTrue(vault.paused());

        // Resolve as rejected
        disputes.resolveDispute(disputeId, false);

        assertFalse(vault.paused());
        assertEq(
            uint256(vault.state()),
            uint256(IProjectVault.VaultState.Active)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL GOVERNANCE HELPER
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Helper function to pass a governance proposal with a given action. It simulates the proposal, voting, and execution process, ensuring that the proposal is successfully enacted.
     * @param action The governance action to propose and execute.
     * @return id The ID of the passed proposal.
     */
    function _passGovernanceProposal(
        IGovernanceModule.Action action
    ) internal returns (uint256 id) {
        id = governance.propose(action);

        vm.prank(alice);
        governance.vote(id, IGovernanceModule.Vote.Yes);

        vm.prank(bob);
        governance.vote(id, IGovernanceModule.Vote.Yes);

        vm.warp(block.timestamp + governance.VOTING_PERIOD() + 1);
        governance.execute(id);
    }
}
