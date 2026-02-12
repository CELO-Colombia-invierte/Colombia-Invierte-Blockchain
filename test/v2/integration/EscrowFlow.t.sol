// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
import {GovernanceModule} from "../../../src/contracts/v2/modules/GovernanceModule.sol";
import {DisputesModule} from "../../../src/contracts/v2/modules/DisputesModule.sol";
import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";
import {IGovernanceModule} from "../../../src/interfaces/v2/IGovernanceModule.sol";

/**
 * @notice This test focuses on the escrow flow within the ProjectVault system, simulating a scenario where a buyer deposits funds, the vault is activated, and then a dispute is opened and resolved. It verifies that the vault behaves correctly in response to these actions, including pausing during disputes and closing if a dispute is accepted.
 */
contract EscrowFlowTest is Test {
    ProjectVault vault;
    GovernanceModule governance;
    DisputesModule disputes;
    MockERC20 token;

    address admin = address(this);
    address buyer = address(1);
    address seller = address(2);

    uint256 constant DEPOSIT_AMOUNT = 50 ether;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Sets up the testing environment by deploying the core vault and modules, configuring permissions, allowing the test token, and funding the test user. This function is called before each test to ensure a clean state.
     */
    function setUp() external {
        token = new MockERC20("USD Stable", "USDS");

        vault = new ProjectVault(address(0xBEEF), admin);
        governance = new GovernanceModule(address(vault));
        disputes = new DisputesModule(address(vault));

        // Roles
        vault.grantRole(vault.CONTROLLER_ROLE(), address(governance));
        vault.grantRole(vault.GOVERNANCE_ROLE(), address(governance));
        vault.grantRole(vault.GOVERNANCE_ROLE(), address(disputes));
        vault.grantRole(vault.GUARDIAN_ROLE(), address(disputes));

        vault.setTokenAllowed(address(token), true);

        // Fund buyer
        token.mint(buyer, 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            HAPPY PATH
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Tests the happy path of the escrow flow where a buyer deposits funds, the vault is activated via governance, and then the governance releases funds to the seller without any disputes. It verifies that the balances are updated correctly throughout the process.
     */
    function test_HappyPathRelease() external {
        // 1️⃣ Buyer deposits while Locked
        vm.startPrank(buyer);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(address(token), DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(token.balanceOf(address(vault)), DEPOSIT_AMOUNT);

        // 2️⃣ Activate via governance
        _passProposal(IGovernanceModule.Action.ActivateVault);

        assertEq(uint8(vault.state()), uint8(ProjectVault.VaultState.Active));

        // 3️⃣ Governance releases funds (governance has CONTROLLER_ROLE)
        governanceReleaseToSeller(DEPOSIT_AMOUNT);

        assertEq(token.balanceOf(seller), DEPOSIT_AMOUNT);
        assertEq(token.balanceOf(address(vault)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        DISPUTE FLOW
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Tests the dispute flow where a buyer deposits funds, the vault is activated, a dispute is opened by the buyer, and then resolved as accepted, leading to the vault being closed. It verifies that the vault is paused during the dispute and that it transitions to the closed state if the dispute is accepted.
     */
    function test_DisputeFlowClosesVault() external {
        // Deposit
        vm.startPrank(buyer);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(address(token), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Activate
        _passProposal(IGovernanceModule.Action.ActivateVault);

        // Open dispute
        vm.prank(buyer);
        uint256 id = disputes.openDispute("Work not delivered");

        // Vault should be paused but still Active
        assertTrue(vault.paused());
        assertEq(uint8(vault.state()), uint8(ProjectVault.VaultState.Active));

        // Resolve dispute as accepted (→ close vault)
        disputes.resolveDispute(id, true);

        assertEq(uint8(vault.state()), uint8(ProjectVault.VaultState.Closed));
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Helper function to pass a governance proposal for a given action. It simulates the proposal creation, voting by both buyer and seller, and execution after the voting period. This function is used to streamline the process of activating the vault or performing other governance actions within the tests.
     */
    function _passProposal(
        IGovernanceModule.Action action
    ) internal returns (uint256 id) {
        id = governance.propose(action);

        vm.prank(buyer);
        governance.vote(id, IGovernanceModule.Vote.Yes);

        vm.prank(seller);
        governance.vote(id, IGovernanceModule.Vote.Yes);

        vm.warp(block.timestamp + governance.VOTING_PERIOD() + 1);

        governance.execute(id);
    }

    /**
     * @notice Helper function to simulate the governance releasing funds to the seller. Since the governance module has the CONTROLLER_ROLE, it can call the release function on the vault directly. This abstracts away the details of how the release is triggered in the tests, allowing for cleaner test code when simulating fund releases.
     */
    function governanceReleaseToSeller(uint256 amount) internal {
        // governance already has CONTROLLER_ROLE
        vm.prank(address(governance));
        vault.release(address(token), seller, amount);
    }
}
