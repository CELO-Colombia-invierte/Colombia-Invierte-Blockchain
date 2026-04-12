// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import {IERC20, SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import {IFeeManager} from '../../../interfaces/v2/IFeeManager.sol';
import {INatilleraV2} from '../../../interfaces/v2/INatilleraV2.sol';
import {IProjectVault} from '../../../interfaces/v2/IProjectVault.sol';

/**
 * @title NatilleraV2
 * @notice Savings circle (natillera) module with quota payments, penalties, yield returns, and fee settlement.
 * @dev Clonable via EIP-1167. Members join, pay quotas, and claim final pool after maturity.
 * @author Key Lab Technical Team.
 */
contract NatilleraV2 is Initializable, ReentrancyGuardUpgradeable, INatilleraV2 {
  using SafeERC20 for IERC20;

  bytes32 internal constant NATILLERA_V2 = keccak256('NATILLERA_V2');
  uint256 internal constant BPS = 10_000;

  IProjectVault public vault;
  IFeeManager public feeManager;
  IERC20 public depositToken;

  uint256 public quota;
  uint256 public duration;
  uint256 public startTimestamp;
  uint256 public paymentCycleDuration;
  uint16 public latePenaltyBps;

  uint256 public maxMembers;
  uint256 public memberCount;

  uint256 public override totalShares;
  uint256 public totalClaimed;
  uint256 public finalPool;
  uint256 public totalDeposited;
  uint256 public protocolFee;
  uint256 public totalYieldReturned;
  bool public poolFinalized;
  bool public feesSettled;

  mapping(address => bool) public isMember;
  mapping(address => mapping(uint256 => bool)) public paidMonth;
  mapping(address => uint256) public userShares;
  mapping(address => bool) public claimed;

  modifier whenVaultOperational() {
    _whenVaultOperational();
    _;
  }

  modifier whenVaultClosed() {
    _whenVaultClosed();
    _;
  }

  function _whenVaultOperational() internal view {
    if (vault.paused()) revert VaultPaused();
    if (vault.state() != IProjectVault.VaultState.Active) {
      revert InvalidVaultState();
    }
  }

  function _whenVaultClosed() internal view {
    if (vault.paused()) revert VaultPaused();
    if (vault.state() != IProjectVault.VaultState.Closed) {
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

  function initialize(
    address vault_,
    address feeManager_,
    address depositToken_,
    uint256 quota_,
    uint256 duration_,
    uint256 startTimestamp_,
    uint256 paymentCycleDuration_,
    uint16 latePenaltyBps_,
    uint256 maxMembers_
  ) external initializer {
    if (vault_ == address(0) || feeManager_ == address(0) || depositToken_ == address(0)) {
      revert ZeroAddress();
    }
    if (startTimestamp_ < block.timestamp) revert InvalidStartTimestamp();
    if (duration_ == 0 || paymentCycleDuration_ == 0) {
      revert InvalidConfig();
    }
    if (maxMembers_ == 0) revert InvalidConfig();
    if (latePenaltyBps_ > BPS) revert InvalidConfig();

    __ReentrancyGuard_init();

    vault = IProjectVault(vault_);
    feeManager = IFeeManager(feeManager_);
    depositToken = IERC20(depositToken_);

    quota = quota_;
    duration = duration_;
    startTimestamp = startTimestamp_;
    paymentCycleDuration = paymentCycleDuration_;

    latePenaltyBps = latePenaltyBps_;
    maxMembers = maxMembers_;
  }

  /*//////////////////////////////////////////////////////////////
                              MEMBERSHIP
  //////////////////////////////////////////////////////////////*/

  function join() external whenVaultOperational {
    if (isMatured()) revert CycleClosed();
    if (isMember[msg.sender]) revert AlreadyMember();
    if (memberCount >= maxMembers) revert MaxMembersReached();

    isMember[msg.sender] = true;
    unchecked {
      memberCount++;
    }
    emit Joined(msg.sender);
  }

  /*//////////////////////////////////////////////////////////////
                              PAYMENT
  //////////////////////////////////////////////////////////////*/

  function currentMonth() public view returns (uint256) {
    if (block.timestamp < startTimestamp) return 0;
    uint256 elapsed = block.timestamp - startTimestamp;
    uint256 month = (elapsed / paymentCycleDuration) + 1;
    if (month > duration) return duration;
    return month;
  }

  function payQuota(uint256 monthId) external whenVaultOperational {
    if (poolFinalized) revert CycleClosed();
    if (isMatured()) revert CycleClosed();
    if (!isMember[msg.sender]) revert NotMember();
    if (monthId == 0 || monthId > duration) revert InvalidMonth();
    if (paidMonth[msg.sender][monthId]) revert AlreadyPaid();

    uint256 monthNow = currentMonth();
    if (monthNow == 0) {
      if (monthId != 1) revert InvalidMonth();
    } else {
      if (monthId > monthNow + 1) revert InvalidMonth();
    }
    uint256 penalty = monthId < monthNow ? (quota * latePenaltyBps) / BPS : 0;

    uint256 totalPayment = quota + penalty;

    vault.depositFrom(msg.sender, address(depositToken), totalPayment);

    (uint256 feePortion,) = feeManager.calculateFee(NATILLERA_V2, quota);
    vault.reserveFees(address(depositToken), feePortion);

    paidMonth[msg.sender][monthId] = true;
    userShares[msg.sender] += quota;
    totalShares += quota;
    totalDeposited += totalPayment;
    emit QuotaPaid(msg.sender, monthId);
  }

  /*//////////////////////////////////////////////////////////////
                              MATURITY
  //////////////////////////////////////////////////////////////*/

  function isMatured() public view returns (bool) {
    return block.timestamp >= startTimestamp + (duration * paymentCycleDuration);
  }

  /*//////////////////////////////////////////////////////////////
                          YIELD / RETURN FUNDS
  //////////////////////////////////////////////////////////////*/

  function returnYield(uint256 amount, address source) external nonReentrant {
    if (poolFinalized) revert CycleClosed();
    if (amount == 0) revert ZeroAmount();

    vault.depositYield(msg.sender, address(depositToken), amount);
    totalYieldReturned += amount;

    emit YieldReturned(msg.sender, source, amount);
  }

  /*//////////////////////////////////////////////////////////////
                              CLAIM
  //////////////////////////////////////////////////////////////*/

  function claimFinal() external nonReentrant whenVaultClosed {
    if (!feesSettled) revert NotFinalized();
    if (totalClaimed >= finalPool) revert FullyClaimed();
    if (!isMatured()) revert NotMatured();
    if (claimed[msg.sender]) revert AlreadyClaimed();
    if (totalShares == 0) revert ZeroShares();

    uint256 shares = userShares[msg.sender];
    if (shares == 0) revert ZeroShares();
    if (!poolFinalized) revert NotFinalized();

    uint256 rawAmount = (shares * finalPool) / totalShares;
    if (rawAmount == 0) revert ZeroClaim();

    uint256 remaining = finalPool - totalClaimed;
    rawAmount = rawAmount > remaining ? remaining : rawAmount;

    uint256 net = rawAmount;
    uint256 newTotalClaimed = totalClaimed + rawAmount;
    claimed[msg.sender] = true;
    totalClaimed = newTotalClaimed;

    vault.releaseOnClose(address(depositToken), msg.sender, net);

    emit Claimed(msg.sender, net);
  }

  function finalizePool() external whenVaultClosed {
    if (msg.sender != address(vault)) revert Unauthorized();
    if (poolFinalized) revert AlreadyFinalized();

    uint256 balance = vault.totalBalance(address(depositToken));
    uint256 reserved = vault.reservedFees(address(depositToken));

    if (balance == 0) revert ZeroPool();
    if (balance < reserved) revert InvalidState();

    (uint256 expectedFee,) = feeManager.calculateFee(NATILLERA_V2, balance);
    uint256 effectiveFee = expectedFee > reserved ? expectedFee : reserved;

    protocolFee = effectiveFee;
    finalPool = balance - effectiveFee;

    poolFinalized = true;

    emit PoolFinalized(finalPool);
  }

  function settleFees() external whenVaultClosed {
    if (!poolFinalized) revert NotFinalized();
    if (feesSettled) revert AlreadyFinalized();

    uint256 reserved = vault.reservedFees(address(depositToken));
    address treasury = feeManager.feeTreasury();

    if (reserved > 0) {
      vault.consumeReservedFees(address(depositToken), reserved);
      vault.releaseOnClose(address(depositToken), treasury, reserved);
    }

    if (protocolFee > reserved) {
      uint256 remaining = protocolFee - reserved;
      vault.releaseOnClose(address(depositToken), treasury, remaining);
    }

    feesSettled = true;

    emit FeesSettled(reserved, protocolFee);
  }

  function isStakeholder(address user) external view override returns (bool) {
    return isMember[user];
  }
}
