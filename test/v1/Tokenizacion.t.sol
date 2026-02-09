// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Tokenizacion} from "../../src/contracts/v1/Tokenizacion.sol";
import {ITokenizacion} from "../../src/interfaces/v1/ITokenizacion.sol";
import {MockERC20} from "../../src/contracts/mocks/shared/MockERC20.sol";

contract TokenizacionTest is Test {
    Tokenizacion sale;
    MockERC20 payment;

    address owner = address(1);
    address buyer = address(2);

    function setUp() public {
        payment = new MockERC20("USD", "USD");

        sale = new Tokenizacion();

        ITokenizacion.Config memory config = ITokenizacion.Config({
            totalTokens: 1000,
            pricePerToken: 1 ether,
            saleStart: block.timestamp + 1 days,
            saleDuration: 7 days,
            paymentToken: address(payment)
        });

        ITokenizacion.ProjectInfo memory info = ITokenizacion.ProjectInfo({
            platform: address(0),
            projectId: 1,
            creator: owner
        });

        vm.prank(owner);
        sale.initialize(config, info);

        payment.mint(buyer, 1000 ether);
        vm.prank(buyer);
        payment.approve(address(sale), type(uint256).max);
    }

    function testBuyTokensERC20() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(buyer);
        sale.buyTokens(10);

        assertEq(sale.tokensSold(), 10);
    }

    function testCannotBuyBeforeStart() public {
        vm.prank(buyer);
        vm.expectRevert(ITokenizacion.SaleNotActive.selector);
        sale.buyTokens(1);
    }
}
