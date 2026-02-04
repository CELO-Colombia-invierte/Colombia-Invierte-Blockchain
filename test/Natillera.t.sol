// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Natillera} from "../src/contracts/Natillera.sol";
import {INatillera} from "../src/interfaces/INatillera.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract NatilleraTest is Test {
    Natillera natillera;
    MockERC20 token;

    address owner = address(1);
    address alice = address(2);
    address bob = address(3);

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

        // preparar fondos
        token.mint(alice, 1000 ether);
        token.mint(bob, 1000 ether);

        vm.prank(owner);
        natillera.addMember(alice);

        vm.prank(owner);
        natillera.addMember(bob);

        vm.prank(alice);
        token.approve(address(natillera), type(uint256).max);

        vm.prank(bob);
        token.approve(address(natillera), type(uint256).max);
    }

    function testDepositAndFinalizeAndWithdraw() public {
        // avanzar a inicio
        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        natillera.deposit();

        vm.prank(bob);
        natillera.deposit();

        // avanzar 3 meses
        vm.warp(block.timestamp + 90 days);

        natillera.finalize();

        uint256 aliceShare = natillera.calculateShare(alice);

        uint256 balanceBefore = token.balanceOf(alice);

        vm.prank(alice);
        natillera.withdraw();

        uint256 balanceAfter = token.balanceOf(alice);

        assertEq(balanceAfter - balanceBefore, aliceShare);
    }

    function testCannotDepositTwiceSameCycle() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        natillera.deposit();

        vm.prank(alice);
        vm.expectRevert(INatillera.AlreadyPaid.selector);
        natillera.deposit();
    }
}
