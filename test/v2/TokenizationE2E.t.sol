// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IRevenueModuleV2} from '../../src/interfaces/v2/IRevenueModuleV2.sol';
import {
  BaseSetup,
  GovernanceModule,
  IProjectVault,
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
}
