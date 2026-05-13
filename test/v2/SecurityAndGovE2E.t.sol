// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IGovernanceModule} from '../../src/interfaces/v2/IGovernanceModule.sol';
import {
  BaseSetup,
  DisputesModule,
  GovernanceModule,
  IGovernanceModule,
  IProjectVault,
  NatilleraV2,
  ProjectVault
} from './BaseSetup.t.sol';

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

  /**
   * @notice Valida que una propuesta exitosa realmente dispare la accion en el Vault.
   */
  function test_GovernanceExecution_Disbursement() public {
    // 1. Setup: user1 se une a la natillera (Quorum base = 1 miembro)
    vm.startPrank(user1);
    usdc.approve(address(vault), type(uint256).max);
    natillera.join();
    vm.stopPrank();

    // 2. Propuesta para desembolsar 10 USDC al user2
    vm.prank(user1);
    uint256 propId =
      gov.propose(IGovernanceModule.Action.Disbursement, 0, 10e18, user2, address(usdc), 'Pago a proveedor');

    // 3. Votacion
    vm.prank(user1);
    gov.vote(propId, IGovernanceModule.Vote.Yes);

    // 4. Warp al final de la votacion
    (,,, uint256 endTime,,,,,,,,,) = gov.proposals(propId);
    vm.warp(endTime + 1);

    // Fondeamos el vault para que tenga dinero que desembolsar
    usdc.mint(address(vault), 50e18);
    uint256 u2BalBefore = usdc.balanceOf(user2);

    // 5. Ejecucion
    gov.execute(propId);

    // 6. Validaciones
    assertEq(usdc.balanceOf(user2) - u2BalBefore, 10e18, 'Los fondos no salieron del Vault');
    (,,,,,,,,,,,, bool executed) = gov.proposals(propId);
    assertTrue(executed, 'La propuesta no se marco como ejecutada');
  }

  /**
   * @notice Valida el fail-safe: Si no hay quorum, la propuesta es rechazada y el contrato no revierte por error interno.
   */
  function test_GovernanceFailsWithoutQuorum() public {
    // 1. Setup: user1 y user2 se unen (Supply total = 2)
    vm.prank(user1);
    usdc.approve(address(vault), type(uint256).max);
    vm.prank(user1);
    natillera.join();

    vm.prank(user2);
    usdc.approve(address(vault), type(uint256).max);
    vm.prank(user2);
    natillera.join();

    // 2. Propuesta
    vm.prank(user1);
    uint256 propId =
      gov.propose(IGovernanceModule.Action.UpdateVotingPeriod, 0, 2 days, address(0), address(0), 'Update');

    // 3. Nadie vota. Saltamos al final del periodo.
    (,,, uint256 endTime,,,,,,,,,) = gov.proposals(propId);
    vm.warp(endTime + 1);

    // 4. Ejecucion ya NO revierte, sino que rechaza el cambio de estado
    gov.execute(propId);

    // 5. Validamos que el periodo de votacion original (1 minutes) NO se modifico (2 days)
    (,,,,,,,,,,,, bool executed) = gov.proposals(propId);
    assertTrue(executed, 'La propuesta debe marcarse como procesada');
    assertEq(gov.votingPeriod(), 1 minutes, 'El periodo no debio cambiar');
  }
}
