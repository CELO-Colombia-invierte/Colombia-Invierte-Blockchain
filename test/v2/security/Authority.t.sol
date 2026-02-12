// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
import {GovernanceModule} from "../../../src/contracts/v2/modules/GovernanceModule.sol";
import {DisputesModule} from "../../../src/contracts/v2/modules/DisputesModule.sol";
import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";

/**
 * @title AuthorityTest
 * @notice Access control validation for Vault + Modules
 * @dev Each test ensures:
 *      1. Contract is in valid state
 *      2. Caller lacks role
 *      3. Revert happens because of authority
 */
contract AuthorityTest is Test {
    ProjectVault vault;
    GovernanceModule governance;
    DisputesModule disputes;
    MockERC20 token;

    address admin = address(this);
    address attacker = address(0xBAD);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() external {
        token = new MockERC20("USD Stable", "USDS");

        vault = new ProjectVault(address(0xBEEF), admin);
        governance = new GovernanceModule(address(vault));
        disputes = new DisputesModule(address(vault));

        // Proper role configuration
        vault.grantRole(vault.CONTROLLER_ROLE(), address(governance));
        vault.grantRole(vault.GOVERNANCE_ROLE(), address(governance));
        vault.grantRole(vault.GOVERNANCE_ROLE(), address(disputes));
        vault.grantRole(vault.GUARDIAN_ROLE(), address(disputes));

        // Remove dummy controller
        vault.revokeRole(vault.CONTROLLER_ROLE(), address(0xBEEF));

        vault.setTokenAllowed(address(token), true);
    }

    /*//////////////////////////////////////////////////////////////
                            CONTROLLER
    //////////////////////////////////////////////////////////////*/

    function test_OnlyControllerCanActivate() external {
        vm.prank(attacker);
        vm.expectRevert();
        vault.activate();
    }

    function test_OnlyControllerCanRelease() external {
        vm.prank(attacker);
        vm.expectRevert();
        vault.release(address(token), attacker, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    function test_OnlyGovernanceCanClose() external {
        // Put vault in Active state first
        vault.grantRole(vault.CONTROLLER_ROLE(), address(this));
        vault.activate();

        vm.prank(attacker);
        vm.expectRevert();
        vault.close();
    }

    function test_OnlyGovernanceCanUnpause() external {
        // Put vault in paused state first
        vault.grantRole(vault.GUARDIAN_ROLE(), address(this));
        vault.pause();

        vm.prank(attacker);
        vm.expectRevert();
        vault.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            GUARDIAN
    //////////////////////////////////////////////////////////////*/

    function test_OnlyGuardianCanPause() external {
        // Remove guardian role from this contract
        vault.revokeRole(vault.GUARDIAN_ROLE(), address(this));

        vm.prank(attacker);
        vm.expectRevert();
        vault.pause();
    }

    /*//////////////////////////////////////////////////////////////
                        DISPUTE AUTHORITY
    //////////////////////////////////////////////////////////////*/

    function test_DisputeResolveRequiresGovernanceRole() public {
        vault.grantRole(vault.CONTROLLER_ROLE(), address(this));
        vault.activate();

        vm.prank(address(1));
        uint256 id = disputes.openDispute("test");

        vault.revokeRole(vault.GOVERNANCE_ROLE(), address(disputes));

        vm.expectRevert(); // 🔥 Correcto según arquitectura actual
        disputes.resolveDispute(id, true);
    }
}
