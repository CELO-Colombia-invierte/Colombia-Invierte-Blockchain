// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {NatilleraV2} from "../../../src/contracts/v2/natillera/NatilleraV2.sol";
import {FeeManager} from "../../../src/contracts/v2/fees/FeeManager.sol";
import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";

interface IProjectVaultMinimal {
    enum VaultState {
        Locked,
        Active,
        Closed
    }

    function state() external view returns (VaultState);

    function depositFrom(address from, address token, uint256 amount) external;

    function releaseOnClose(address token, address to, uint256 amount) external;
}

contract MockVault is IProjectVaultMinimal {
    MockERC20 public token;
    VaultState public override state;

    constructor(address _token) {
        token = MockERC20(_token);
        state = VaultState.Active;
    }

    function setClosed() external {
        state = VaultState.Closed;
    }

    function depositFrom(
        address from,
        address,
        uint256 amount
    ) external override {
        bool success = token.transferFrom(from, address(this), amount);
        require(success);
    }

    function releaseOnClose(
        address,
        address to,
        uint256 amount
    ) external override {
        require(state == VaultState.Closed, "NOT_CLOSED");
        bool success = token.transfer(to, amount);
        require(success);
    }
}

/**
 * @title NatilleraV2Test
 * @notice Fuzz and invariant tests for NatilleraV2 with fee integration.
 */
contract NatilleraV2Test is Test {
    NatilleraV2 internal natillera;
    MockVault internal vault;
    FeeManager internal feeManager;
    MockERC20 internal token;

    address internal alice = address(0x1);
    address internal bob = address(0x2);
    address internal carol = address(0x3);

    uint256 internal constant QUOTA = 1e18;
    uint256 internal constant DURATION = 12;

    function setUp() public {
        token = new MockERC20("Mock", "MOCK");
        vault = new MockVault(address(token));
        feeManager = new FeeManager();

        feeManager.initialize(address(999)); // treasury mock

        natillera = new NatilleraV2();
        natillera.initialize(
            address(vault),
            address(feeManager),
            address(token),
            QUOTA,
            DURATION,
            block.timestamp
        );
    }

    // =============================================================
    // FUZZ: PROPORTIONAL DISTRIBUTION
    // =============================================================

    /**
     * @notice Verifies that funds are distributed proportionally to shares.
     */
    function testFuzz_DistributionProportional(
        uint96 monthsA,
        uint96 monthsB
    ) public {
        monthsA = uint96(bound(monthsA, 1, DURATION));
        monthsB = uint96(bound(monthsB, 1, DURATION));

        uint256 amountA = monthsA * QUOTA;
        uint256 amountB = monthsB * QUOTA;

        token.mint(alice, amountA);
        token.mint(bob, amountB);

        // Alice
        vm.startPrank(alice);
        token.approve(address(vault), amountA);
        natillera.join();
        for (uint256 i; i < monthsA; i++) {
            natillera.payQuota(i + 1);
        }
        vm.stopPrank();

        // Bob
        vm.startPrank(bob);
        token.approve(address(vault), amountB);
        natillera.join();
        for (uint256 i; i < monthsB; i++) {
            natillera.payQuota(i + 1);
        }
        vm.stopPrank();

        vm.warp(block.timestamp + 400 days);

        vault.setClosed();

        uint256 vaultBefore = token.balanceOf(address(vault));

        vm.prank(alice);
        natillera.claimFinal();

        vm.prank(bob);
        natillera.claimFinal();

        uint256 vaultAfter = token.balanceOf(address(vault));

        assertEq(vaultAfter, 0);

        uint256 usersTotal = token.balanceOf(alice) + token.balanceOf(bob);

        uint256 treasuryBalance = token.balanceOf(feeManager.feeTreasury());

        assertEq(usersTotal + treasuryBalance, vaultBefore);
    }

    // =============================================================
    // DOUBLE CLAIM PROTECTION
    // =============================================================

    /**
     * @notice Tests that a user cannot claim twice.
     */
    function testCannotClaimTwice() public {
        token.mint(alice, QUOTA);

        vm.startPrank(alice);
        token.approve(address(vault), QUOTA);
        natillera.join();
        natillera.payQuota(1);
        vm.stopPrank();

        vm.warp(block.timestamp + 400 days);
        vault.setClosed();

        vm.prank(alice);
        natillera.claimFinal();

        vm.expectRevert();
        vm.prank(alice);
        natillera.claimFinal();
    }

    // =============================================================
    // REVERT BEFORE MATURE
    // =============================================================

    /**
     * @notice Tests that claim reverts if cycle hasn't matured.
     */
    function testCannotClaimBeforeMature() public {
        token.mint(alice, QUOTA);

        vm.startPrank(alice);
        token.approve(address(vault), QUOTA);
        natillera.join();
        natillera.payQuota(1);
        vm.stopPrank();

        vault.setClosed();

        vm.expectRevert();
        vm.prank(alice);
        natillera.claimFinal();
    }

    // =============================================================
    // REVERT IF VAULT NOT CLOSED
    // =============================================================

    /**
     * @notice Tests that claim reverts if vault is not closed.
     */
    function testCannotClaimIfVaultNotClosed() public {
        token.mint(alice, QUOTA);

        vm.startPrank(alice);
        token.approve(address(vault), QUOTA);
        natillera.join();
        natillera.payQuota(1);
        vm.stopPrank();

        vm.warp(block.timestamp + 400 days);

        vm.expectRevert();
        vm.prank(alice);
        natillera.claimFinal();
    }

    // =============================================================
    // ZERO SHARES
    // =============================================================

    /**
     * @notice Tests that user with zero shares cannot claim.
     */
    function testZeroSharesCannotClaim() public {
        vm.warp(block.timestamp + 400 days);
        vault.setClosed();

        vm.expectRevert();
        vm.prank(alice);
        natillera.claimFinal();
    }

    // =============================================================
    // MULTI USER INVARIANT
    // =============================================================

    /**
     * @notice Verifies total distribution equals initial vault balance.
     */
    function testFuzz_MultiUserInvariant(uint96 a, uint96 b, uint96 c) public {
        a = uint96(bound(a, 1, DURATION));
        b = uint96(bound(b, 1, DURATION));
        c = uint96(bound(c, 1, DURATION));

        token.mint(alice, a * QUOTA);
        token.mint(bob, b * QUOTA);
        token.mint(carol, c * QUOTA);

        _participate(alice, a);
        _participate(bob, b);
        _participate(carol, c);

        vm.warp(block.timestamp + 400 days);
        vault.setClosed();

        uint256 vaultBefore = token.balanceOf(address(vault));

        vm.prank(alice);
        natillera.claimFinal();

        vm.prank(bob);
        natillera.claimFinal();

        vm.prank(carol);
        natillera.claimFinal();

        uint256 vaultAfter = token.balanceOf(address(vault));

        assertEq(vaultAfter, 0);

        uint256 distributed = token.balanceOf(alice) +
            token.balanceOf(bob) +
            token.balanceOf(carol);

        uint256 treasuryBalance = token.balanceOf(feeManager.feeTreasury());

        assertEq(distributed + treasuryBalance, vaultBefore);
    }

    // =============================================================
    // INTERNAL HELPER
    // =============================================================

    function _participate(address user, uint256 months) internal {
        vm.startPrank(user);

        token.approve(address(vault), months * QUOTA);
        natillera.join();

        for (uint256 i; i < months; i++) {
            natillera.payQuota(i + 1);
        }

        vm.stopPrank();
    }
}
