// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IRevenueModuleV2} from '../../src/interfaces/v2/IRevenueModuleV2.sol';
import {BaseSetup, GovernanceModule, ProjectTokenV2, ProjectVault, RevenueModuleV2} from './BaseSetup.t.sol';

/**
 * @title TokenizationE2E
 * @notice End-to-end tests for tokenization project including dust prevention and revenue distribution.
 * @author Key Lab Technical Team.
 */
contract TokenizationE2E is BaseSetup {
  RevenueModuleV2 public revenue;
  ProjectVault public vault;
  ProjectTokenV2 public token;
  GovernanceModule public gov;

  uint256 constant TARGET = 10_000e18;
  uint256 constant MIN_CAP = 5000e18;
  uint256 constant PRICE = 100e18;

  function setUp() public override {
    super.setUp();
    vm.prank(creator);
    uint256 id = platform.createTokenizationProject(address(usdc), TARGET, MIN_CAP, PRICE, 30 days, 'Token', 'TKN');

    (address vaultAddr, address modAddr, address tokenAddr,, address govAddr,,) = platform.projects(id);

    vault = ProjectVault(vaultAddr);
    revenue = RevenueModuleV2(modAddr);
    token = ProjectTokenV2(tokenAddr);
    gov = GovernanceModule(govAddr);
  }

  /**
   * @notice Invest must reject amounts that are not multiples of tokenPrice (dust prevention).
   */
  function test_InvestRevertsOnDustLoss() public {
    vm.startPrank(user1);
    usdc.approve(address(vault), type(uint256).max);

    vm.expectRevert(IRevenueModuleV2.InvalidAmount.selector);
    revenue.invest(105e18);

    (uint256 valid, uint256 remainder) = revenue.getMaxInvestable(105e18);
    assertEq(valid, 100e18);
    assertEq(remainder, 5e18);

    revenue.invest(valid);
    assertEq(token.balanceOf(user1), 1);
    vm.stopPrank();
  }

  /**
   * @notice Revenue distribution must correctly allocate proportional rewards.
   */
  function test_RevenueDistributionMath() public {
    address[2] memory users = [user1, user2];
    for (uint256 i = 0; i < 2; i++) {
      vm.startPrank(users[i]);
      usdc.approve(address(vault), type(uint256).max);
      revenue.invest(5000e18);
      vm.stopPrank();
    }

    vm.warp(block.timestamp + 31 days);
    vm.prank(address(gov));
    revenue.finalizeSale();

    usdc.mint(creator, 1000e18);
    vm.startPrank(creator);
    usdc.approve(address(vault), 1000e18);
    revenue.depositRevenue(1000e18);
    vm.stopPrank();

    assertEq(revenue.pending(user1), 500e18);
    assertEq(revenue.pending(user2), 500e18);

    uint256 balBefore = usdc.balanceOf(user1);
    vm.prank(user1);
    revenue.claim();
    assertEq(usdc.balanceOf(user1) - balBefore, 500e18);

    assertEq(revenue.pending(user1), 0);
  }
}
