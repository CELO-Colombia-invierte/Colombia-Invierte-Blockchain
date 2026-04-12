// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseSetup, NatilleraV2, ProjectVault} from './BaseSetup.t.sol';

/**
 * @title NatilleraE2E
 * @notice End-to-end test for natillera lifecycle including yield returns and fee settlement.
 * @author Key Lab Technical Team.
 */
contract NatilleraE2E is BaseSetup {
  NatilleraV2 public natillera;
  ProjectVault public vault;

  uint256 constant QUOTA = 100e18;

  function setUp() public override {
    super.setUp();
    vm.prank(creator);
    uint256 id = platform.createNatilleraProject(address(usdc), QUOTA, 12, 10);

    (address vaultAddr, address modAddr,,, address govAddr,,) = platform.projects(id);

    vault = ProjectVault(vaultAddr);
    natillera = NatilleraV2(modAddr);

    vm.prank(govAddr);
    vault.activate();
  }

  function test_FullNatilleraLifecycleWithYield() public {
    address[3] memory users = [user1, user2, user3];
    for (uint256 i = 0; i < 3; i++) {
      vm.startPrank(users[i]);
      usdc.approve(address(vault), type(uint256).max);
      natillera.join();
      natillera.payQuota(1);
      vm.stopPrank();
    }

    assertEq(vault.totalBalance(address(usdc)), 300e18);
    assertEq(vault.reservedFees(address(usdc)), 9e18);

    vm.prank(address(natillera));
    vault.release(address(usdc), admin, 200e18);

    usdc.mint(admin, 50e18);
    vm.startPrank(admin);
    usdc.approve(address(vault), 250e18);
    natillera.returnYield(250e18, admin);
    vm.stopPrank();

    assertEq(natillera.totalYieldReturned(), 250e18);

    vm.warp(block.timestamp + 365 days);
    assertTrue(natillera.isMatured());

    (,,,, address govAddr,,) = platform.projects(1);
    vm.prank(govAddr);
    vault.close();

    vm.prank(address(vault));
    natillera.finalizePool();

    natillera.settleFees();

    assertEq(natillera.protocolFee(), 10.5e18);

    vm.prank(user1);
    natillera.claimFinal();

    uint256 user1Balance = usdc.balanceOf(user1);
    assertTrue(user1Balance > 100_000e18);
  }
}
