// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProjectTokenV2} from "../../../src/contracts/v2/tokenization/ProjectTokenV2.sol";
import {RevenueModuleV2} from "../../../src/contracts/v2/tokenization/RevenueModuleV2.sol";
import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";

/**
 * @title RevenueModuleFuzz
 * @notice Fuzz testing for RevenueModuleV2 invariants and edge cases.
 */
contract RevenueModuleFuzz is Test {
    ProjectTokenV2 token;
    RevenueModuleV2 revenue;
    MockERC20 settlement;

    address alice = address(0x1);
    address bob = address(0x2);
    address carol = address(0x3);
    address vault = address(0x4);
    address governance = address(this);

    uint256 constant FUNDING_TARGET = 1_000_000e18;
    uint256 constant TOKEN_PRICE = 1e18;

    function setUp() public {
        settlement = new MockERC20("USDC", "USDC");

        settlement.mint(alice, 10_000_000e18);
        settlement.mint(bob, 10_000_000e18);
        settlement.mint(carol, 10_000_000e18);

        token = new ProjectTokenV2();
        token.initialize(
            "ProjectToken",
            "PT",
            10_000_000e18,
            governance,
            governance
        );

        revenue = new RevenueModuleV2();
        revenue.initialize(
            address(token),
            vault,
            address(settlement),
            FUNDING_TARGET,
            TOKEN_PRICE,
            block.timestamp,
            block.timestamp + 30 days,
            block.timestamp + 60 days,
            1000,
            governance
        );

        token.setRevenueModule(address(revenue));
        token.grantRole(token.MINTER_ROLE(), address(revenue));
        token.enableTransfers();
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _depositRevenue(uint256 amount) internal {
        settlement.mint(vault, amount);

        vm.prank(vault);
        settlement.approve(address(revenue), amount);

        revenue.depositRevenue(amount);
    }

    /*//////////////////////////////////////////////////////////////
                        1. CONSERVATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Verifies that total claimed rewards never exceed total deposited revenue.
     */
    function testFuzz_conservationOfValue(
        uint96 investA,
        uint96 investB,
        uint96 revenue1,
        uint96 revenue2
    ) public {
        investA = uint96(bound(investA, 1e18, 1_000e18));
        investB = uint96(bound(investB, 1e18, 1_000e18));
        revenue1 = uint96(bound(revenue1, 1e18, 1_000e18));
        revenue2 = uint96(bound(revenue2, 1e18, 1_000e18));

        vm.startPrank(alice);
        settlement.approve(address(revenue), investA);
        revenue.invest(investA);
        vm.stopPrank();

        vm.startPrank(bob);
        settlement.approve(address(revenue), investB);
        revenue.invest(investB);
        vm.stopPrank();

        _depositRevenue(revenue1);

        vm.startPrank(alice);

        uint256 amount = token.balanceOf(alice) / 2;
        bool success = token.transfer(carol, amount);
        require(success);

        vm.stopPrank();

        _depositRevenue(revenue2);

        uint256 totalRevenue = revenue1 + revenue2;

        uint256 beforeA = settlement.balanceOf(alice);
        uint256 beforeB = settlement.balanceOf(bob);
        uint256 beforeC = settlement.balanceOf(carol);

        vm.prank(alice);
        try revenue.claim() {} catch {}

        vm.prank(bob);
        try revenue.claim() {} catch {}

        vm.prank(carol);
        try revenue.claim() {} catch {}

        uint256 claimed = (settlement.balanceOf(alice) - beforeA) +
            (settlement.balanceOf(bob) - beforeB) +
            (settlement.balanceOf(carol) - beforeC);

        assertLe(claimed, totalRevenue);
    }

    /*//////////////////////////////////////////////////////////////
                        2. NO RETROACTIVE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Ensures late investors cannot claim rewards from before their investment.
     */
    function testFuzz_noRetroactiveYield(
        uint96 investA,
        uint96 revenue1,
        uint96 investLate
    ) public {
        investA = uint96(bound(investA, 1e18, 1_000e18));
        revenue1 = uint96(bound(revenue1, 1e18, 1_000e18));
        investLate = uint96(bound(investLate, 1e18, 1_000e18));

        vm.startPrank(alice);
        settlement.approve(address(revenue), investA);
        revenue.invest(investA);
        vm.stopPrank();

        _depositRevenue(revenue1);

        vm.startPrank(bob);
        settlement.approve(address(revenue), investLate);
        revenue.invest(investLate);
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert();
        revenue.claim();
    }

    /*//////////////////////////////////////////////////////////////
                        3. TRANSFER INVARIANCE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Verifies that historical rewards don't transfer with tokens.
     */
    function testFuzz_transferResetsPending(
        uint96 investA,
        uint96 revenue1
    ) public {
        investA = uint96(bound(investA, 1e18, 1_000e18));
        revenue1 = uint96(bound(revenue1, 1e18, 1_000e18));

        // Alice invests
        vm.startPrank(alice);
        settlement.approve(address(revenue), investA);
        revenue.invest(investA);
        vm.stopPrank();

        // Deposit revenue
        _depositRevenue(revenue1);

        // Should have pending rewards
        uint256 pendingBefore = revenue.pending(alice);
        assertGt(pendingBefore, 0);

        // Transfer all tokens
        vm.startPrank(alice);
        uint256 balance = token.balanceOf(alice);
        bool success = token.transfer(bob, balance);
        require(success);
        vm.stopPrank();

        // Historical pending does not travel
        assertEq(revenue.pending(alice), 0);
        assertEq(revenue.pending(bob), 0);

        // Contract retains the balance
        uint256 contractBalance = settlement.balanceOf(address(revenue));
        assertGe(contractBalance, revenue1);
    }

    /**
     * @notice Verifies that claiming before transfer preserves rewards.
     */
    function testFuzz_claimBeforeTransferKeepsRewards(
        uint96 investA,
        uint96 revenue1
    ) public {
        investA = uint96(bound(investA, 1e18, 1_000e18));
        revenue1 = uint96(bound(revenue1, 1e18, 1_000e18));

        vm.startPrank(alice);
        settlement.approve(address(revenue), investA);
        revenue.invest(investA);
        vm.stopPrank();

        _depositRevenue(revenue1);

        uint256 balanceBefore = settlement.balanceOf(alice);

        vm.prank(alice);
        revenue.claim();

        uint256 balanceAfter = settlement.balanceOf(alice);

        uint256 claimed = balanceAfter - balanceBefore;
        assertTrue(claimed <= revenue1);
        assertTrue(revenue1 - claimed <= 2); // Allow for rounding
    }
}
