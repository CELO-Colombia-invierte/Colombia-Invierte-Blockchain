// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IProjectVault} from '../../../interfaces/v2/IProjectVault.sol';
import {AccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import {IERC20, SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title ProjectVault (Final Production Version)
 * @notice Custody layer for V2 projects with funding model support and fee reservation.
 * @dev Minimal, deterministic, non-upgradable logic via clones.
 * @author Key Lab Technical Team.
 */
contract ProjectVault is
  Initializable,
  AccessControlUpgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable,
  IProjectVault
{
  using SafeERC20 for IERC20;

  /*//////////////////////////////////////////////////////////////
                              ROLES
  //////////////////////////////////////////////////////////////*/

  bytes32 public constant CONTROLLER_ROLE = keccak256('CONTROLLER_ROLE');
  bytes32 public constant GUARDIAN_ROLE = keccak256('GUARDIAN_ROLE');

  /*//////////////////////////////////////////////////////////////
                              STATE
  //////////////////////////////////////////////////////////////*/

  VaultState public state;
  FundingModel public model;
  address public project;
  uint256 public activeDisputeId;

  mapping(address => uint256) public reservedFees;
  mapping(address => bool) public isTokenAllowed;

  /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor() {
    _disableInitializers();
  }

  /*//////////////////////////////////////////////////////////////
                              INITIALIZER
  //////////////////////////////////////////////////////////////*/

  function initialize(
    address project_,
    address governance_,
    address guardian_,
    address allowedToken_,
    FundingModel _model
  ) external initializer {
    if (project_ == address(0) || governance_ == address(0) || guardian_ == address(0) || allowedToken_ == address(0)) revert ZeroAddress();

    __AccessControl_init();
    __Pausable_init();
    __ReentrancyGuard_init();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

    project = project_;
    state = VaultState.Active;
    model = _model;

    _grantRole(GUARDIAN_ROLE, guardian_);
    _grantRole(CONTROLLER_ROLE, project_);

    isTokenAllowed[allowedToken_] = true;
    emit VaultInitialized(project_, governance_);
    emit TokenAllowed(allowedToken_, true);
    emit Activated();
  }

  /*//////////////////////////////////////////////////////////////
                          TOKEN CONFIG
  //////////////////////////////////////////////////////////////*/

  function setTokenAllowed(address token, bool allowed) external onlyRole(GUARDIAN_ROLE) {
    if (!allowed && IERC20(token).balanceOf(address(this)) > 0) {
      revert InvalidState();
    }
    isTokenAllowed[token] = allowed;
    emit TokenAllowed(token, allowed);
  }

  /*//////////////////////////////////////////////////////////////
                          DEPOSIT
  //////////////////////////////////////////////////////////////*/

  function depositFrom(
    address from,
    address token,
    uint256 amount
  ) external whenNotPaused nonReentrant onlyRole(CONTROLLER_ROLE) {
    if (state != VaultState.Active) revert InvalidState();
    if (!isTokenAllowed[token]) revert TokenNotAllowed();
    if (amount == 0) revert ZeroAmount();

    IERC20(token).safeTransferFrom(from, address(this), amount);
    emit Deposited(token, from, amount);
  }

  function depositYield(address from, address token, uint256 amount) external nonReentrant onlyRole(CONTROLLER_ROLE) {
    if (!isTokenAllowed[token]) revert TokenNotAllowed();
    if (amount == 0) revert ZeroAmount();

    IERC20(token).safeTransferFrom(from, address(this), amount);
    emit YieldDeposited(token, from, amount);
  }

  function reserveFees(address token, uint256 amount) external onlyRole(CONTROLLER_ROLE) {
    if (model != FundingModel.Natillera) revert InvalidModel();
    if (!isTokenAllowed[token]) revert TokenNotAllowed();
    if (amount == 0) revert ZeroAmount();

    uint256 balance = IERC20(token).balanceOf(address(this));
    if (reservedFees[token] + amount > balance) {
      revert InsufficientBalance();
    }

    reservedFees[token] += amount;
    emit FeesReserved(amount);
  }

  function totalBalance(address token) external view returns (uint256) {
    return IERC20(token).balanceOf(address(this));
  }

  function consumeReservedFees(address token, uint256 amount) external onlyRole(CONTROLLER_ROLE) {
    if (amount > reservedFees[token]) revert InvalidState();
    reservedFees[token] -= amount;
    emit ReservedFeesConsumed(amount);
  }

  function availableBalance(address token) public view returns (uint256) {
    uint256 balance = IERC20(token).balanceOf(address(this));
    if (model == FundingModel.Natillera) {
      uint256 reserved = reservedFees[token];
      if (reserved > balance) return 0;
      return balance - reserved;
    }
    return balance;
  }

  /*//////////////////////////////////////////////////////////////
                      STATE TRANSITIONS
  //////////////////////////////////////////////////////////////*/

  function activate() external onlyRole(CONTROLLER_ROLE) {
    if (state != VaultState.Locked) revert InvalidState();
    state = VaultState.Active;
    emit Activated();
  }

  function close() external onlyRole(CONTROLLER_ROLE) {
    if (state != VaultState.Active) revert InvalidState();
    state = VaultState.Closed;
    emit Closed();
  }

  /*//////////////////////////////////////////////////////////////
                          RELEASE
  //////////////////////////////////////////////////////////////*/

  function release(
    address token,
    address to,
    uint256 amount
  ) external nonReentrant whenNotPaused onlyRole(CONTROLLER_ROLE) {
    if (state != VaultState.Active) revert InvalidVaultState();
    if (amount == 0) revert ZeroAmount();
    if (to == address(0)) revert ZeroAddress();
    if (!isTokenAllowed[token]) revert TokenNotAllowed();

    uint256 balance = IERC20(token).balanceOf(address(this));
    uint256 reserved = model == FundingModel.Natillera ? reservedFees[token] : 0;
    if (reserved > balance) revert InsufficientBalance();

    uint256 available = balance - reserved;
    if (amount > available) revert InsufficientBalance();

    IERC20(token).safeTransfer(to, amount);
    emit Released(token, to, amount);
  }

  function releaseOnClose(
    address token,
    address to,
    uint256 amount
  ) external nonReentrant whenNotPaused onlyRole(CONTROLLER_ROLE) {
    if (state != VaultState.Closed) revert InvalidState();
    if (amount == 0) revert ZeroAmount();
    if (to == address(0)) revert ZeroAddress();
    if (!isTokenAllowed[token]) revert TokenNotAllowed();
    if (amount > IERC20(token).balanceOf(address(this))) {
      revert InsufficientBalance();
    }

    IERC20(token).safeTransfer(to, amount);
    emit Released(token, to, amount);
  }

  /*//////////////////////////////////////////////////////////////
                          EMERGENCY
  //////////////////////////////////////////////////////////////*/

  function pause() external onlyRole(GUARDIAN_ROLE) {
    _pause();
  }

  function unpause() external onlyRole(GUARDIAN_ROLE) {
    if (activeDisputeId != 0) revert CannotUnfreezeDispute();
    _unpause();
  }

  function paused() public view override(PausableUpgradeable, IProjectVault) returns (bool) {
    return super.paused();
  }

  function freezeByDispute(uint256 disputeId) external onlyRole(CONTROLLER_ROLE) {
    if (paused()) revert InvalidState();
    activeDisputeId = disputeId;
    _pause();
    emit FrozenByDispute(disputeId);
  }

  function unfreezeFromDispute() external onlyRole(CONTROLLER_ROLE) {
    if (activeDisputeId == 0) revert InvalidState();
    activeDisputeId = 0;
    _unpause();
    emit UnfrozenFromDispute();
  }
}
