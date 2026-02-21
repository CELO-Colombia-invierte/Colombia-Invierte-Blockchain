// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {NatilleraV2} from "../../../src/contracts/v2/natillera/NatilleraV2.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";
import {INatilleraV2} from "../../../src/interfaces/v2/INatilleraV2.sol";

/**
 * @title NatilleraInvariantsTest
 * @notice Invariant tests for NatilleraV2 to ensure mathematical correctness.
 */
contract NatilleraInvariantsTest is Test {
    NatilleraV2 natillera;
    ProjectVault vault;
    MockERC20 token;

    address[] internal members;

    uint256 constant QUOTA = 100e18;
    uint256 constant DURATION = 12;

    function setUp() public {
        token = new MockERC20("Mock", "MOCK");

        natillera = new NatilleraV2();
        vault = new ProjectVault();

        vault.initialize(address(natillera), address(this), address(this));

        vault.setTokenAllowed(address(token), true);

        natillera.initialize(
            address(vault),
            address(token),
            QUOTA,
            DURATION,
            block.timestamp
        );

        // Create 5 deterministic members
        for (uint256 i = 0; i < 5; i++) {
            address member = makeAddr(
                string(abi.encodePacked("member", vm.toString(i)))
            );
            members.push(member);

            token.mint(member, QUOTA);

            vm.startPrank(member);
            token.approve(address(vault), QUOTA);
            natillera.join();
            natillera.payQuota(1);
            vm.stopPrank();
        }

        // Mature the system
        vm.warp(block.timestamp + 400 days);

        vault.activate();
        vault.close();
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT 1
    totalClaimed never exceeds finalPool
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Verifies that total claimed never exceeds final pool balance.
     */
    function testInvariant_TotalClaimedNeverExceedsFinalPool() public {
        uint256 vaultBefore = token.balanceOf(address(vault));

        for (uint256 i = 0; i < members.length; i++) {
            vm.prank(members[i]);
            natillera.claimFinal();
        }

        uint256 finalPool = natillera.finalPool();
        uint256 totalClaimed = natillera.totalClaimed();

        assertLe(totalClaimed, finalPool);
        assertEq(totalClaimed, vaultBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT 2
    Sum of final balances equals initial vault balance
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Verifies that no value is created or lost during distribution.
     */
    function testInvariant_NoValueCreationOrLoss() public {
        uint256 vaultBefore = token.balanceOf(address(vault));

        uint256 totalReceived;

        for (uint256 i = 0; i < members.length; i++) {
            address member = members[i];

            uint256 before = token.balanceOf(member);

            vm.prank(member);
            natillera.claimFinal();

            uint256 afterBal = token.balanceOf(member);

            totalReceived += (afterBal - before);
        }

        assertEq(totalReceived, vaultBefore);
        assertEq(token.balanceOf(address(vault)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT 3
    Cannot claim twice
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that double claims are prevented.
     */
    function testInvariant_CannotClaimTwice() public {
        address member = members[0];

        vm.prank(member);
        natillera.claimFinal();

        vm.prank(member);
        vm.expectRevert(INatilleraV2.AlreadyClaimed.selector);
        natillera.claimFinal();
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT 4
    Random claim order doesn't break math
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Verifies that claim order doesn't affect final distribution.
     */
    function testInvariant_RandomClaimOrder() public {
        uint256 vaultBefore = token.balanceOf(address(vault));

        // Reverse order
        for (uint256 i = members.length; i > 0; i--) {
            vm.prank(members[i - 1]);
            natillera.claimFinal();
        }

        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(natillera.totalClaimed(), vaultBefore);
    }
}
