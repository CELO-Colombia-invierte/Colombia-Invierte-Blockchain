// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {NatilleraV2} from "../../../src/contracts/v2/natillera/NatilleraV2.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";
import {INatilleraV2} from "../../../src/interfaces/v2/INatilleraV2.sol";

/**
 * @title NatilleraPostMaturityTest
 * @notice Tests NatilleraV2 behavior after maturity and vault closure.
 */
contract NatilleraPostMaturityTest is Test {
    NatilleraV2 natillera;
    ProjectVault vault;
    MockERC20 token;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    uint256 constant QUOTA = 100e18;
    uint256 constant DURATION = 12;

    function setUp() public {
        token = new MockERC20("Mock", "MOCK");

        // 1️⃣ Deploy empty contracts
        natillera = new NatilleraV2();
        vault = new ProjectVault();

        // 2️⃣ Initialize vault FIRST with natillera as project
        vault.initialize(
            address(natillera), // project (controller)
            address(this), // governance
            address(this) // guardian
        );

        // 3️⃣ Allow deposit token
        vault.setTokenAllowed(address(token), true);

        // 4️⃣ Initialize natillera
        natillera.initialize(
            address(vault),
            address(token),
            QUOTA,
            DURATION,
            block.timestamp
        );

        // Mint tokens
        token.mint(alice, QUOTA);
        token.mint(bob, QUOTA);
    }

    function _joinAndPay(address user) internal {
        vm.startPrank(user);

        token.approve(address(vault), QUOTA);

        natillera.join();
        natillera.payQuota(1);

        vm.stopPrank();
    }

    function _matureAndClose() internal {
        vm.warp(block.timestamp + 400 days);

        // Vault must move to Active first
        vault.activate();
        vault.close();
    }

    /*//////////////////////////////////////////////////////////////
                                TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that new members cannot join after maturity.
     */
    function test_CannotJoinAfterMaturity() public {
        _joinAndPay(alice);
        _matureAndClose();

        vm.prank(bob);
        vm.expectRevert(INatilleraV2.CycleClosed.selector);
        natillera.join();
    }

    /**
     * @notice Tests that quota payments cannot be made after maturity.
     */
    function test_CannotPayQuotaAfterMaturity() public {
        _joinAndPay(alice);
        _matureAndClose();

        vm.prank(alice);
        vm.expectRevert(INatilleraV2.CycleClosed.selector);
        natillera.payQuota(1);
    }

    /**
     * @notice Tests that a user cannot claim twice.
     */
    function test_CannotClaimTwice() public {
        _joinAndPay(alice);
        _matureAndClose();

        vm.prank(alice);
        natillera.claimFinal();

        vm.prank(alice);
        vm.expectRevert(INatilleraV2.AlreadyClaimed.selector);
        natillera.claimFinal();
    }

    /**
     * @notice Verifies vault balance is zero after all claims.
     */
    function test_VaultBalanceZeroAfterAllClaims() public {
        _joinAndPay(alice);
        _joinAndPay(bob);

        _matureAndClose();

        uint256 before = token.balanceOf(address(vault));

        vm.prank(alice);
        natillera.claimFinal();

        vm.prank(bob);
        natillera.claimFinal();

        uint256 afterBalance = token.balanceOf(address(vault));

        assertEq(afterBalance, 0);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), before);
    }
}
