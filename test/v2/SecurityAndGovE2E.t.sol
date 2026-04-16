// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IGovernanceModule} from '../../src/interfaces/v2/IGovernanceModule.sol';
import {BaseSetup, DisputesModule, GovernanceModule, IProjectVault, NatilleraV2, ProjectVault} from './BaseSetup.t.sol';

/**
 * @title SecurityAndGovE2E
 * @notice End-to-end tests for governance snapshot immutability and dispute state machine.
 * @author Key Lab Technical Team.
 */
contract SecurityAndGovE2E is BaseSetup {
  NatilleraV2 public natillera;
  ProjectVault public vault;
  GovernanceModule public gov;
  DisputesModule public disputes;

  function setUp() public override {
    super.setUp();

    vm.startPrank(creator);
    uint256 id = platform.createNatilleraProject(address(usdc), 100e18, 12, 10);
    vm.stopPrank();

    (address vaultAddr, address modAddr,,, address govAddr, address dispAddr,) = platform.projects(id);

    vault = ProjectVault(vaultAddr);
    natillera = NatilleraV2(modAddr);
    gov = GovernanceModule(govAddr);
    disputes = DisputesModule(dispAddr);
  }

  /**
   * @notice Governance snapshot immutability: active proposals unaffected by parameter changes.
   */
  function test_GovernanceSnapshotImmutability() public {
    vm.prank(user1);
    usdc.approve(address(vault), type(uint256).max);
    vm.prank(user1);
    natillera.join();

    vm.prank(user1);
    uint256 propId = gov.propose(IGovernanceModule.Action.Disbursement, 0, 10e18, user2, address(usdc), 'Test');

    (,,, uint256 endTime,,,,,,,,,) = gov.proposals(propId);

    vm.prank(user1);
    gov.propose(IGovernanceModule.Action.UpdateVotingPeriod, 0, 10 days, address(0), address(0), 'Update');

    (,,, uint256 endTimeAfter,,,,,,,,,) = gov.proposals(propId);
    assertEq(endTime, endTimeAfter, 'Temporal snapshot failed, proposal was altered');
  }

  /**
   * @notice Dispute state machine and guardian protection against unfreeze.
   */
  function test_DisputeStateMachineAndGuardianProtection() public {
    vm.prank(user1);
    natillera.join();

    vm.prank(user1);
    uint256 disputeId = disputes.openDispute('Fraude detectado');

    assertFalse(vault.paused(), 'Opening dispute must not pause vault directly');

    vm.startPrank(address(gov));
    disputes.markFrozen(disputeId);
    vault.freezeByDispute(disputeId);
    vm.stopPrank();

    assertTrue(vault.paused(), 'Vault should be paused by dispute');
    assertEq(vault.activeDisputeId(), disputeId, 'Vault must track dispute ID');

    vm.startPrank(creator);
    vault.grantRole(vault.GUARDIAN_ROLE(), admin);
    vm.stopPrank();

    vm.startPrank(admin);
    vm.expectRevert(IProjectVault.CannotUnfreezeDispute.selector);
    vault.unpause();
    vm.stopPrank();

    vm.prank(address(gov));
    vault.unfreezeFromDispute();

    assertFalse(vault.paused(), 'Vault should be unpaused');
    assertEq(vault.activeDisputeId(), 0, 'Dispute ID must be cleared');
  }
}
