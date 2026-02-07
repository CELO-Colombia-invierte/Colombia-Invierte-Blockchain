// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Natillera} from "../../src/contracts/v1/Natillera.sol";
import {INatillera} from "../../src/interfaces/v1/INatillera.sol";
import {MockERC20} from "../mocks/v1/MockERC20.sol";

contract NatilleraTest is Test {
    Natillera natillera;
    MockERC20 token;

    address owner = address(1);
    address alice = address(2);
    address bob = address(3);
    address carol = address(4);

    function setUp() public {
        token = new MockERC20("Mock", "MOCK");
        natillera = new Natillera();

        INatillera.Config memory config = INatillera.Config({
            token: address(token),
            monthlyContribution: 100 ether,
            totalMonths: 3,
            maxMembers: 5
        });

        INatillera.ProjectInfo memory info = INatillera.ProjectInfo({
            platform: address(0),
            projectId: 1,
            creator: owner
        });

        vm.prank(owner);
        natillera.initialize(block.timestamp + 1 days, config, info);

        // fondos
        token.mint(alice, 1000 ether);
        token.mint(bob, 1000 ether);
        token.mint(carol, 1000 ether);

        // miembros
        vm.prank(owner);
        natillera.addMember(alice);
        vm.prank(owner);
        natillera.addMember(bob);
        vm.prank(owner);
        natillera.addMember(carol);

        // approvals
        vm.prank(alice);
        token.approve(address(natillera), type(uint256).max);
        vm.prank(bob);
        token.approve(address(natillera), type(uint256).max);
        vm.prank(carol);
        token.approve(address(natillera), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            HAPPY PATH
    //////////////////////////////////////////////////////////////*/

    function testDepositFinalizeWithdraw() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        natillera.deposit();
        vm.prank(bob);
        natillera.deposit();

        vm.warp(block.timestamp + 90 days);
        natillera.finalize();

        uint256 aliceShare = natillera.calculateShare(alice);

        uint256 balanceBefore = token.balanceOf(alice);

        vm.prank(alice);
        natillera.withdraw();

        uint256 balanceAfter = token.balanceOf(alice);

        assertEq(balanceAfter - balanceBefore, aliceShare);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT RULES
    //////////////////////////////////////////////////////////////*/

    function testCannotDepositTwiceSameCycle() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        natillera.deposit();

        vm.prank(alice);
        vm.expectRevert(INatillera.AlreadyPaid.selector);
        natillera.deposit();
    }

    function testNonMemberCannotDeposit() public {
        vm.warp(block.timestamp + 2 days);

        address stranger = address(99);
        token.mint(stranger, 100 ether);

        vm.prank(stranger);
        token.approve(address(natillera), type(uint256).max);

        vm.prank(stranger);
        vm.expectRevert(INatillera.NotMember.selector);
        natillera.deposit();
    }

    /*//////////////////////////////////////////////////////////////
                            FINALIZE RULES
    //////////////////////////////////////////////////////////////*/

    function testCannotFinalizeBeforeEnd() public {
        // avanzar a después del inicio
        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        natillera.deposit();

        // no importa el motivo exacto, solo que NO se pueda finalizar
        vm.expectRevert();
        natillera.finalize();
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW RULES
    //////////////////////////////////////////////////////////////*/

    function testCannotWithdrawBeforeFinalize() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        natillera.deposit();

        vm.prank(alice);
        vm.expectRevert(INatillera.NotFinalized.selector);
        natillera.withdraw();
    }

    function testCannotWithdrawTwice() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        natillera.deposit();

        vm.warp(block.timestamp + 90 days);
        natillera.finalize();

        vm.prank(alice);
        natillera.withdraw();

        vm.prank(alice);
        vm.expectRevert(INatillera.AlreadyWithdrawn.selector);
        natillera.withdraw();
    }

    function testMemberWithoutDepositCannotWithdraw() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        natillera.deposit();

        vm.warp(block.timestamp + 90 days);
        natillera.finalize();

        vm.prank(carol);
        vm.expectRevert(INatillera.InvalidAmount.selector);
        natillera.withdraw();
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    function testSharesAreProportional() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        natillera.deposit();
        vm.prank(bob);
        natillera.deposit();

        vm.warp(block.timestamp + 90 days);
        natillera.finalize();

        uint256 aliceShare = natillera.calculateShare(alice);
        uint256 bobShare = natillera.calculateShare(bob);

        assertEq(aliceShare, bobShare);
        assertEq(aliceShare + bobShare, 200 ether);
    }
}
