// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IMilestonesModule} from '../../../interfaces/v2/IMilestonesModule.sol';
import {IProjectVault} from '../../../interfaces/v2/IProjectVault.sol';
import {IRevenueModuleV2} from '../../../interfaces/v2/IRevenueModuleV2.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';

/**
 * @title MilestonesModule
 * @notice Manages the lifecycle of project milestones from proposal to execution.
 * @dev Clonable via EIP-1167. Only governance can propose, approve, and execute milestones.
 * @author Key Lab Technical Team.
 */
contract MilestonesModule is Initializable, ReentrancyGuardUpgradeable, IMilestonesModule {
  IProjectVault public vault;
  IRevenueModuleV2 public revenue;
  address public governance;
  uint256 public override milestoneCount;
  mapping(address => uint256) public totalCommittedByToken;
  mapping(uint256 => Milestone) public override milestones;

  /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor() {
    _disableInitializers();
  }

  /*//////////////////////////////////////////////////////////////
                              INITIALIZER
  //////////////////////////////////////////////////////////////*/

  function initialize(address vault_, address governance_, address revenue_) external initializer {
    if (vault_ == address(0) || governance_ == address(0) || revenue_ == address(0)) revert ZeroAddress();

    __ReentrancyGuard_init();

    vault = IProjectVault(vault_);
    governance = governance_;
    revenue = IRevenueModuleV2(revenue_);

    emit MilestonesInitialized(vault_, governance_);
  }

  /*//////////////////////////////////////////////////////////////
                              MODIFIERS
  //////////////////////////////////////////////////////////////*/

  modifier onlyGovernance() {
    _onlyGovernance();
    _;
  }

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
                          MILESTONE LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Creates a new milestone proposal with fund availability check.
   */
  function proposeMilestone(
    string calldata description,
    address token,
    address recipient,
    uint256 amount
  ) external override onlyGovernance whenVaultOperational returns (uint256 id) {
    if (!revenue.saleFinalized()) revert FundingNotFinalized();
    if (token == address(0) || recipient == address(0)) {
      revert ZeroAddress();
    }
    if (amount == 0) revert ZeroAmount();
    if (!vault.isTokenAllowed(token)) revert InvalidToken();

    uint256 available = vault.availableBalance(token);
    uint256 committed = totalCommittedByToken[token];

    if (committed + amount > available) revert InsufficientAvailableFunds();

    totalCommittedByToken[token] = committed + amount;

    id = ++milestoneCount;
    bytes32 descriptionHash = keccak256(bytes(description));
    milestones[id] = Milestone({
      descriptionHash: descriptionHash,
      token: token,
      recipient: recipient,
      amount: amount,
      status: MilestoneStatus.Proposed
    });
    emit MilestoneProposed(id, msg.sender, token, recipient, amount, description);
  }

  function approveMilestone(uint256 id) external override onlyGovernance whenVaultOperational {
    if (id == 0 || id > milestoneCount) revert InvalidMilestone();
    Milestone storage m = milestones[id];
    if (m.status != MilestoneStatus.Proposed) revert InvalidState();
    m.status = MilestoneStatus.Approved;
    emit MilestoneApproved(id);
  }

  function executeMilestone(uint256 id) external override onlyGovernance nonReentrant whenVaultOperational {
    if (id == 0 || id > milestoneCount) revert InvalidMilestone();
    Milestone storage m = milestones[id];
    if (!revenue.saleFinalized()) revert FundingNotFinalized();
    if (m.status != MilestoneStatus.Approved) revert InvalidState();
    if (_availableBalance(m.token) < m.amount) {
      revert InsufficientAvailableFunds();
    }

    vault.release(m.token, m.recipient, m.amount);
    totalCommittedByToken[m.token] -= m.amount;
    m.status = MilestoneStatus.Executed;
    emit MilestoneExecuted(id);
  }

  /*//////////////////////////////////////////////////////////////
                              INTERNAL
  //////////////////////////////////////////////////////////////*/

  function _onlyGovernance() internal view {
    if (msg.sender != governance) revert Unauthorized();
  }

  function _availableBalance(address token) internal view returns (uint256) {
    uint256 available = vault.availableBalance(token);
    uint256 committed = totalCommittedByToken[token];
    if (committed > available) return 0;
    return available - committed;
  }
}
