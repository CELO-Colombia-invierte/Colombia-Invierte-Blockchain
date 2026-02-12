// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
import {GovernanceModule} from "../../../src/contracts/v2/modules/GovernanceModule.sol";
import {DisputesModule} from "../../../src/contracts/v2/modules/DisputesModule.sol";
import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";

/**
 * @notice Test suite for basic invariants of the ProjectVault contract.
 */
contract BasicInvariantsTest is StdInvariant, Test {
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

    /*//////////////////////////////////////////////////////////////
                                    SETUP 
        //////////////////////////////////////////////////////////////*/
    /** @notice Sets up the testing environment by deploying the core vault and modules, configuring permissions, and allowing the test token. This function is called before each test to ensure a clean state.
     */
    function setUp() external {
        token = new MockERC20("USD Stable", "USDS");

        vault = new ProjectVault(address(0xDEAD), admin);
        governance = new GovernanceModule(address(vault));
        disputes = new DisputesModule(address(vault));

        vault.grantRole(vault.CONTROLLER_ROLE(), address(governance));
        vault.grantRole(vault.GOVERNANCE_ROLE(), address(governance));
        vault.grantRole(vault.GUARDIAN_ROLE(), address(governance));
        vault.grantRole(vault.GUARDIAN_ROLE(), address(disputes));
        vault.grantRole(vault.GOVERNANCE_ROLE(), address(disputes));

        targetContract(address(vault));
        targetContract(address(governance));
        targetContract(address(disputes));
    }

    /*//////////////////////////////////////////////////////////////
                            INVARIANTS
    //////////////////////////////////////////////////////////////*/
    /** @notice Invariant that checks that once a vault is closed, it cannot be reactivated. This ensures that the Closed state is terminal and prevents any further state changes that could lead to inconsistencies or security issues.
     */
    function invariant_ClosedIsTerminal() public {
        if (vault.state() == ProjectVault.VaultState.Closed) {
            vm.expectRevert();
            vault.activate();
        }
    }

    /** @notice Invariant that checks that funds cannot be released from the vault unless it is in an active state. This ensures that the release function can only be successfully called when the vault is active, preventing unauthorized access to funds in other states.
     */
    function invariant_NoReleaseWhenNotActive() public {
        if (vault.state() != ProjectVault.VaultState.Active) {
            vm.expectRevert();
            vault.release(address(token), address(0x1), 1 ether);
        }
    }
}
