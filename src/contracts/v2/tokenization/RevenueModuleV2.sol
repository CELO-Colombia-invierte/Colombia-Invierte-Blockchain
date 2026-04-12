// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import {IERC20, SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import {IFeeManager} from '../../../interfaces/v2/IFeeManager.sol';
import {IProjectTokenV2} from '../../../interfaces/v2/IProjectTokenV2.sol';
import {IProjectVault} from '../../../interfaces/v2/IProjectVault.sol';
import {IRevenueModuleV2} from '../../../interfaces/v2/IRevenueModuleV2.sol';

/**
 * @title RevenueModuleV2
 * @notice Manages investment, refunds, revenue distribution and fee handling for tokenization projects.
 * @dev Clonable via EIP-1167. Handles funding lifecycle and reward accrual.
 * @author Key Lab Technical Team.
 */
contract RevenueModuleV2 is Initializable, ReentrancyGuardUpgradeable, IRevenueModuleV2 {
  using SafeERC20 for IERC20;

  uint256 internal constant PRECISION = 1e12;
  bytes32 internal constant MODULE_ID = keccak256('TOKENIZATION_V2');

  /*//////////////////////////////////////////////////////////////
                              STORAGE
  //////////////////////////////////////////////////////////////*/

  IProjectTokenV2 public token;
  IProjectVault public vault;
  IFeeManager public feeManager;
  IERC20 public settlementToken;

  address public governance;
  address public projectCreator;

  uint256 public pendingRevenue;

  uint128 public fundingTarget;
  uint128 public minimumCap;
  uint128 public tokenPrice;

  uint64 public saleStart;
  uint64 public saleEnd;
  uint64 public distributionEnd;

  uint16 public expectedApy;

  uint128 public totalRaised;
  uint128 public accRewardPerShare;

  bool public saleFinalized;

  mapping(address => uint256) public investments;
  mapping(address => uint256) public rewardDebt;

  modifier whenVaultOperational() {
    _whenVaultOperational();
    _;
  }

  function _whenVaultOperational() internal view {
    if (vault.paused()) revert VaultPaused();
    if (vault.state() != IProjectVault.VaultState.Active) {
      revert InvalidVaultState();
    }
  }

  /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor() {
    _disableInitializers();
  }

  /*//////////////////////////////////////////////////////////////
                          INITIALIZE
  //////////////////////////////////////////////////////////////*/

  function initialize(InitParams calldata p) external initializer {
    if (
      p.token == address(0) || p.vault == address(0) || p.settlementToken == address(0) || p.governance == address(0)
        || p.projectCreator == address(0) || p.feeManager == address(0)
    ) revert Unauthorized();
    if (p.saleStart >= p.saleEnd || p.saleEnd >= p.distributionEnd) {
      revert InvalidState();
    }

    __ReentrancyGuard_init();

    token = IProjectTokenV2(p.token);
    vault = IProjectVault(p.vault);
    settlementToken = IERC20(p.settlementToken);
    feeManager = IFeeManager(p.feeManager);

    fundingTarget = uint128(p.fundingTarget);
    minimumCap = uint128(p.minimumCap);
    tokenPrice = uint128(p.tokenPrice);

    saleStart = uint64(p.saleStart);
    saleEnd = uint64(p.saleEnd);
    distributionEnd = uint64(p.distributionEnd);

    expectedApy = p.expectedApy;

    governance = p.governance;
    projectCreator = p.projectCreator;
  }

  /*//////////////////////////////////////////////////////////////
                              STATE
  //////////////////////////////////////////////////////////////*/

  function state() public view override returns (State) {
    uint256 ts = block.timestamp;
    if (ts < saleStart) return State.Pending;
    if (ts <= saleEnd) {
      if (totalRaised >= fundingTarget) return State.Successful;
      return State.Active;
    }
    if (totalRaised >= minimumCap) return State.Successful;
    return State.Failed;
  }

  /*//////////////////////////////////////////////////////////////
                              INVEST
  //////////////////////////////////////////////////////////////*/

  function invest(uint256 amount) external nonReentrant whenVaultOperational {
    updatePool();

    if (state() != State.Active) revert SaleClosed();
    if (amount == 0) revert ZeroAmount();
    if (amount % tokenPrice != 0) revert InvalidAmount();

    uint128 raised = totalRaised;
    if (raised + amount > fundingTarget) revert FundingTargetReached();
    if (amount > type(uint128).max - raised) revert InvalidState();

    uint256 userBalance = IERC20(address(token)).balanceOf(msg.sender);
    uint256 accumulated = (userBalance * accRewardPerShare) / PRECISION;
    uint256 pendingRewards;

    if (accumulated > rewardDebt[msg.sender]) {
      pendingRewards = accumulated - rewardDebt[msg.sender];
    }

    uint256 tokensToMint = amount / tokenPrice;
    // casting to 'uint128' is safe because we check that 'amount' does not exceed 'fundingTarget' which is a 'uint128'
    // forge-lint: disable-next-line(unsafe-typecast)
    uint128 amount128 = uint128(amount);

    totalRaised = raised + amount128;
    investments[msg.sender] += amount;

    vault.depositFrom(msg.sender, address(settlementToken), amount);

    if (pendingRewards > 0) {
      vault.release(address(settlementToken), msg.sender, pendingRewards);
    }

    token.mint(msg.sender, tokensToMint);

    uint256 newBalance = IERC20(address(token)).balanceOf(msg.sender);
    rewardDebt[msg.sender] = (newBalance * accRewardPerShare) / PRECISION;

    emit Invested(msg.sender, amount, tokensToMint);
  }

  /*//////////////////////////////////////////////////////////////
                          FINALIZE
  //////////////////////////////////////////////////////////////*/

  function finalizeSale() external nonReentrant {
    if (msg.sender != governance) revert Unauthorized();
    if (state() != State.Successful || saleFinalized) revert InvalidState();
    if (totalRaised < minimumCap) revert BelowMinimumCap();

    saleFinalized = true;

    uint256 balance = vault.totalBalance(address(settlementToken));
    if (balance < totalRaised) revert InvalidState();

    (uint256 fee, uint256 net) = feeManager.calculateFee(MODULE_ID, balance);
    address treasury = feeManager.feeTreasury();

    if (treasury == address(0)) revert Unauthorized();

    vault.release(address(settlementToken), treasury, fee);
    vault.release(address(settlementToken), projectCreator, net);
    emit SaleFinalized();
  }

  /*//////////////////////////////////////////////////////////////
                              REFUND
  //////////////////////////////////////////////////////////////*/

  function refund() external nonReentrant {
    if (state() != State.Failed) revert InvalidState();

    uint256 invested = investments[msg.sender];
    if (invested == 0) revert NothingToClaim();

    investments[msg.sender] = 0;

    uint256 bal = IERC20(address(token)).balanceOf(msg.sender);
    if (bal > 0) {
      token.burn(msg.sender, bal);
    }

    vault.releaseOnClose(address(settlementToken), msg.sender, invested);
    emit Refunded(msg.sender, invested);
  }

  /*//////////////////////////////////////////////////////////////
                      REWARD DISTRIBUTION
  //////////////////////////////////////////////////////////////*/

  function depositRevenue(uint256 amount) external nonReentrant whenVaultOperational {
    if (state() != State.Successful) revert InvalidState();
    if (!saleFinalized) revert InvalidState();
    if (amount == 0) revert ZeroAmount();

    vault.depositFrom(msg.sender, address(settlementToken), amount);
    pendingRevenue += amount;

    emit RevenueDeposited(amount);
  }

  function claim() external nonReentrant whenVaultOperational {
    if (!saleFinalized) revert InvalidState();
    if (block.timestamp > distributionEnd) revert DistributionEnded();

    uint256 balance = IERC20(address(token)).balanceOf(msg.sender);
    updatePool();
    uint256 accumulated = (balance * accRewardPerShare) / PRECISION;
    uint256 debt = rewardDebt[msg.sender];

    if (accumulated <= debt) revert NothingToClaim();

    uint256 claimable = accumulated - debt;
    rewardDebt[msg.sender] = accumulated;

    vault.release(address(settlementToken), msg.sender, claimable);
    emit Claimed(msg.sender, claimable);
  }

  function pending(address user) external view override returns (uint256) {
    uint256 _acc = accRewardPerShare;
    uint256 supply = IERC20(address(token)).totalSupply();

    if (supply > 0) {
      // casting to 'uint128' is safe because the maximum value of 'pendingRevenue' is limited by the total amount deposited, which cannot exceed 'fundingTarget' (a 'uint128'), and 'supply' is at least 1, so the result of '(pendingRevenue * PRECISION) / supply' will always fit within 'uint128'
      // forge-lint: disable-next-line(unsafe-typecast)
      _acc += uint128((pendingRevenue * PRECISION) / supply);
    }

    uint256 balance = IERC20(address(token)).balanceOf(user);
    uint256 accumulated = (balance * _acc) / PRECISION;
    uint256 debt = rewardDebt[user];

    return accumulated <= debt ? 0 : accumulated - debt;
  }

  /*//////////////////////////////////////////////////////////////
                      TOKEN HOOK
  //////////////////////////////////////////////////////////////*/

  function beforeTokenTransfer(address from, address to, uint256 amount) external override {
    if (msg.sender != address(token)) revert Unauthorized();
    updatePool();
    uint256 acc = accRewardPerShare;
    IERC20 t = IERC20(address(token));

    if (from != address(0)) {
      uint256 balanceBefore = t.balanceOf(from);
      uint256 accumulated = (balanceBefore * acc) / PRECISION;
      uint256 pendingRewards = accumulated > rewardDebt[from] ? accumulated - rewardDebt[from] : 0;
      uint256 newBalance = balanceBefore - amount;
      uint256 newAccumulated = (newBalance * acc) / PRECISION;
      rewardDebt[from] = newAccumulated > pendingRewards ? newAccumulated - pendingRewards : 0;
    }

    if (to != address(0)) {
      uint256 balanceBefore = t.balanceOf(to);
      uint256 accumulated = (balanceBefore * acc) / PRECISION;
      uint256 pendingRewards = accumulated > rewardDebt[to] ? accumulated - rewardDebt[to] : 0;
      uint256 newBalance = balanceBefore + amount;
      rewardDebt[to] = ((newBalance * acc) / PRECISION) - pendingRewards;
    }
  }

  function updatePool() public {
    uint256 _pending = pendingRevenue;
    if (_pending == 0) return;

    uint256 supply = IERC20(address(token)).totalSupply();
    if (supply == 0) return;

    uint256 increment = (_pending * PRECISION) / supply;
    if (increment > type(uint128).max) revert InvalidState();

    // casting to 'uint128' is safe because the maximum value of 'increment' is limited by the total amount deposited, which cannot exceed 'fundingTarget' (a 'uint128'), and 'supply' is at least 1, so the result of '(_pending * PRECISION) / supply' will always fit within 'uint128'
    // forge-lint: disable-next-line(unsafe-typecast)
    accRewardPerShare += uint128(increment);
    pendingRevenue = 0;
  }

  function finalizeFailure() external nonReentrant {
    if (state() != State.Failed) revert InvalidState();
    if (block.timestamp < saleEnd) revert InvalidState();
    if (msg.sender != governance) revert Unauthorized();

    if (vault.state() != IProjectVault.VaultState.Closed) {
      vault.close();
    }

    emit SaleFailed();
  }

  function isStakeholder(address user) external view override returns (bool) {
    return token.balanceOf(user) > 0;
  }

  function getMaxInvestable(uint256 amount) external view override returns (uint256 validAmount, uint256 remainder) {
    uint256 price = tokenPrice;
    if (price == 0) return (0, amount);
    remainder = amount % price;
    validAmount = amount - remainder;
  }
}
