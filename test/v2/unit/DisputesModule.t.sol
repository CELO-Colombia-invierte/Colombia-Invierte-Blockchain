// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
import {DisputesModule} from "../../../src/contracts/v2/modules/DisputesModule.sol";

contract DisputesModuleTest is Test {
    ProjectVault vault;
    DisputesModule disputes;

    address project = address(0xA);
    address governance = address(this);
    address guardian = address(0xC);

    function setUp() public {
        vault = new ProjectVault();
        vault.initialize(project, governance, guardian);

        vm.prank(governance);
        vault.activate();

        disputes = new DisputesModule();
        disputes.initialize(address(vault), governance);

        vm.prank(guardian);
        vault.grantRole(vault.GUARDIAN_ROLE(), address(disputes));
    }

    function testOpenDisputeFreezesVault() public {
        disputes.openDispute("issue");

        assertTrue(vault.paused());
    }

    function testResolveAcceptedClosesVault() public {
        uint256 id = disputes.openDispute("issue");

        disputes.resolveDispute(id, true);

        assertTrue(vault.paused());
    }

    function testResolveRejectedUnpausesVault() public {
        uint256 id = disputes.openDispute("issue");

        disputes.resolveDispute(id, false);

        assertTrue(vault.paused());
    }
}
