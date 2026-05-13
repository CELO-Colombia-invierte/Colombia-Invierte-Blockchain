// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
  BaseSetup,
  GovernanceModule,
  IGovernanceModule,
  IMilestonesModule,
  IProjectVault,
  IRevenueModuleV2,
  MilestonesModule,
  ProjectTokenV2,
  ProjectVault,
  RevenueModuleV2
} from './BaseSetup.t.sol';

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
  MilestonesModule public milestones;

  uint256 constant TARGET = 10_000e18;
  uint256 constant MIN_CAP = 5000e18;
  uint256 constant PRICE = 100e18;

  function setUp() public override {
    super.setUp();
    vm.prank(creator);
    uint256 id = platform.createTokenizationProject(address(usdc), TARGET, MIN_CAP, PRICE, 30 days, 'Token', 'TKN');

    (address vaultAddr, address modAddr, address tokenAddr, address msAddr, address govAddr,,) = platform.projects(id);

    vault = ProjectVault(vaultAddr);
    revenue = RevenueModuleV2(modAddr);
    token = ProjectTokenV2(tokenAddr);
    gov = GovernanceModule(govAddr);
    milestones = MilestonesModule(msAddr);
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
    vm.prank(address(creator));
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

  /**
   * @notice Valida el flujo completo de fracaso de ventas y reembolso (Unhappy Path).
   */
  function test_SaleFailureAndRefunds() public {
    // 1. user1 invierte, pero NO llegamos al MIN_CAP (5000e18)
    vm.startPrank(user1);
    usdc.approve(address(vault), type(uint256).max);
    revenue.invest(4000e18);
    vm.stopPrank();

    // 2. Adelantamos el tiempo pasado el saleEnd (30 días)
    vm.warp(block.timestamp + 31 days);

    // 3. El creador oficializa el fracaso
    vm.prank(creator);
    revenue.finalizeFailure();

    assertEq(uint256(revenue.state()), uint256(IRevenueModuleV2.State.Failed), 'El estado deberia ser Failed');
    assertTrue(vault.state() == IProjectVault.VaultState.Closed, 'El Vault deberia estar cerrado');

    // 4. El usuario solicita su reembolso
    uint256 balanceBefore = usdc.balanceOf(user1);

    vm.prank(user1);
    revenue.refund();

    // 5. Validaciones: Se recupero el USDC y se quemaron los tokens
    assertEq(usdc.balanceOf(user1) - balanceBefore, 4000e18, 'El reembolso no coincide');
    assertEq(token.balanceOf(user1), 0, 'Los tokens no fueron quemados');
  }

  /**
   * @notice Valida la contabilidad del yield despues de que los usuarios transfieren sus tokens.
   */
  function test_RevenueWithTokenTransfers() public {
    // 1. Inversiones iniciales
    vm.startPrank(user1);
    usdc.approve(address(vault), type(uint256).max);
    revenue.invest(5000e18); // Recibe 50 tokens
    vm.stopPrank();

    vm.startPrank(user2);
    usdc.approve(address(vault), type(uint256).max);
    revenue.invest(5000e18); // Recibe 50 tokens
    vm.stopPrank();

    // 2. Finalizacion
    vm.warp(block.timestamp + 31 days);
    vm.prank(creator);
    revenue.finalizeSale();

    // 3. Se deposita el primer pago de ingresos (Yield)
    usdc.mint(creator, 1000e18);
    vm.startPrank(creator);
    usdc.approve(address(vault), 1000e18);
    revenue.depositRevenue(1000e18);
    vm.stopPrank();

    // Comprobamos que user1 tiene acumulados 500 USDC
    assertEq(revenue.pending(user1), 500e18);

    // 4. Habilitar transferencias (Solo la Gobernanza puede hacerlo)
    vm.prank(address(gov));
    token.enableTransfers();

    // 5. User1 le transfiere la mitad de sus tokens (25) a User3
    uint256 balBeforeTransfer = usdc.balanceOf(user1);
    vm.prank(user1);
    bool success = token.transfer(user3, 25);
    require(success);

    // 6. Validaciones Matematicas Criticas
    // Como el contrato auto-reclama al transferir, validamos que el USDC llegó a la wallet
    uint256 earned = usdc.balanceOf(user1) - balBeforeTransfer;
    assertEq(earned, 500e18, 'No se auto-reclamo el yield al transferir');

    // User3 acaba de recibir los tokens, su yield pendiente historico debe ser 0
    assertEq(revenue.pending(user1), 0, 'Deberia haber reclamado todo');
    assertEq(revenue.pending(user3), 0, 'User3 esta robando yield historico');
  }

  /**
   * @notice Valida el flujo completo: Recaudación -> Finalización -> Hito Propuesto -> Votación SÍ -> Desembolso
   */
  function test_FullLifecycle_MilestoneSuccess() public {
    // 1. Inversión (Llegamos al TARGET de 10,000)
    vm.startPrank(user1);
    usdc.approve(address(vault), type(uint256).max);
    revenue.invest(5000e18);
    token.delegate(user1); // Activar poder de voto
    vm.stopPrank();

    vm.startPrank(user2);
    usdc.approve(address(vault), type(uint256).max);
    revenue.invest(5000e18);
    token.delegate(user2); // Activar poder de voto
    vm.stopPrank();

    // Avanzar el bloque para que el snapshot (block.number - 1) registre los votos
    vm.roll(block.number + 1);

    // 2. Finalizar Venta
    vm.warp(block.timestamp + 31 days);
    vm.prank(creator);
    revenue.finalizeSale();

    // 3. Validar contabilidad inicial (Fee del 30% = 3000, Neto = 7000)
    assertEq(revenue.projectFunds(), 7000e18, 'El neto no se guardo correctamente');
    assertEq(usdc.balanceOf(address(treasury)), 3000e18, 'El fee no llego al treasury');
    assertEq(vault.totalBalance(address(usdc)), 7000e18, 'Los fondos netos no estan en el Vault');

    // 4. El creador propone un Hito (Ej: Pago de cimientos)
    address vendor = address(0x999);
    vm.prank(creator);
    uint256 msId = milestones.proposeMilestone('Cimientos', address(usdc), vendor, 2000e18);

    // Validamos que los fondos quedaron comprometidos
    assertEq(milestones.totalRequestedByToken(address(usdc)), 2000e18);

    // 5. Se crea la propuesta en Gobernanza para aprobar este hito
    vm.prank(user1);
    uint256 propId = gov.propose(
      IGovernanceModule.Action.ApproveAndExecuteMilestone, msId, 0, address(0), address(0), 'Aprobar pago de cimientos'
    );

    // 6. Los inversores votan SÍ
    vm.prank(user1);
    gov.vote(propId, IGovernanceModule.Vote.Yes);
    vm.prank(user2);
    gov.vote(propId, IGovernanceModule.Vote.Yes);

    // 7. Pasa el tiempo de votación y se ejecuta
    (,,, uint256 endTime,,,,,,,,,) = gov.proposals(propId);
    vm.warp(endTime + 1);

    uint256 vendorBalBefore = usdc.balanceOf(vendor);
    gov.execute(propId);

    // 8. Validaciones Finales
    assertEq(usdc.balanceOf(vendor) - vendorBalBefore, 2000e18, 'El proveedor no recibio los fondos');

    (,,,, IMilestonesModule.MilestoneStatus status) = milestones.milestones(msId);
    assertEq(uint256(status), uint256(IMilestonesModule.MilestoneStatus.Executed), 'El estado del hito no es Executed');
  }

  /**
   * @notice Valida el fail-safe: Hito Propuesto -> Votación NO -> Cancelación Automática -> Liberación de Presupuesto
   */
  function test_FullLifecycle_MilestoneRejected() public {
    // 1. Inversión y Finalización
    vm.startPrank(user1);
    usdc.approve(address(vault), type(uint256).max);
    revenue.invest(10_000e18);
    token.delegate(user1); // Activar poder de voto
    vm.stopPrank();

    // Avanzar el bloque para el snapshot histórico
    vm.roll(block.number + 1);

    vm.warp(block.timestamp + 31 days);
    vm.prank(creator);
    revenue.finalizeSale();

    // 2. El creador intenta sacar TODO el dinero de una vez (7000e18 neto)
    vm.prank(creator);
    uint256 msId = milestones.proposeMilestone('Sacar todo el dinero', address(usdc), address(0x999), 7000e18);

    // 3. Propuesta de Gobernanza
    vm.prank(user1);
    uint256 propId = gov.propose(
      IGovernanceModule.Action.ApproveAndExecuteMilestone, msId, 0, address(0), address(0), 'Intento de vaciar el vault'
    );

    // 4. La comunidad vota que NO
    vm.prank(user1);
    gov.vote(propId, IGovernanceModule.Vote.No);

    // 5. Ejecución (Debe fallar silenciosamente y disparar la cancelación)
    (,,, uint256 endTime,,,,,,,,,) = gov.proposals(propId);
    vm.warp(endTime + 1);

    gov.execute(propId);

    // 6. Validaciones Críticas de Seguridad
    // El presupuesto debe volver a estar libre para futuros hitos correctos
    assertEq(milestones.totalRequestedByToken(address(usdc)), 0, 'El totalRequested no se libero al rechazar');
    assertEq(milestones.totalCommittedByToken(address(usdc)), 0, 'El totalCommitted no se libero al rechazar');

    (,,,, IMilestonesModule.MilestoneStatus status) = milestones.milestones(msId);
    assertEq(
      uint256(status), uint256(IMilestonesModule.MilestoneStatus.Cancelled), 'El hito no fue marcado como Cancelado'
    );
  }
}
