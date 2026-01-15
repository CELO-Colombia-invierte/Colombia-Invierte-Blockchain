// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import {Tracking} from 'contracts/Tracking.sol';
import {INatillera} from 'interfaces/INatillera.sol';
import {IPlatform} from 'interfaces/IPlatform.sol';

uint256 constant MES = 30 days;

contract Natillera is Initializable, Tracking, OwnableUpgradeable, INatillera {
  /// @inheritdoc INatillera
  uint256 public cycle;
  /// @inheritdoc INatillera
  uint256 public cycleDueDate;

  /// @notice Deposits of the members
  mapping(address _member => uint256 _deposit) internal _deposits;
  /// @notice Whether a wallet is a member
  mapping(address _wallet => bool _member) internal _isMember;

  /// @notice Project configuration
  NatilleraConfig internal _config;
  /// @notice Members of the natillera
  address[] internal _members;

  /// @notice The start timestamp of the natillera (minus 1 month to sync the first cycle correctly)
  uint256 internal _init;

  /// @notice Sync to current cycle
  modifier sync() {
    _syncCycle();
    _;
  }

  /// @notice Verify member status
  modifier onlyMember() {
    if (!_isMember[msg.sender]) revert Natillera_NotMember();
    _;
  }

  /// @inheritdoc INatillera
  function initialize(
    uint256 _comienzo,
    NatilleraConfig calldata _implConfig,
    IPlatform.GovernanceConfig calldata _govConfig,
    IPlatform.ProjectConfig calldata _projectConfig
  ) external initializer {
    _init = _comienzo - MES;
    (uint256 _uuid, address _owner, address _platform) =
      (_projectConfig.uuid, _projectConfig.creator, _projectConfig.platform);
    uuid = _uuid;
    __Ownable_init(_owner);
    PLATFORM = _platform;
    _config = _implConfig;
    _syncCycle();
  }

  /// --- LOGIC FUNCTIONS ---

  /// @inheritdoc INatillera
  function trackContribution(address _member)
    external sync
    returns (uint256 _amountPaid, uint256 _amountDue, uint256 _missedCycles)
  {
    (_amountPaid, _amountDue, _missedCycles) = _trackContribution(_member);
  }

  /// --- ACCESS CONTROL FUNCTIONS ---

  /// @inheritdoc INatillera
  function depositSingleCycle() external payable onlyMember sync {
    uint256 _amount = msg.value;
    address _member = msg.sender;
    _deposit(_member, 1, _amount);
  }

  /// @inheritdoc INatillera
  function depositMultipleCycles(uint256 _cycles) external payable onlyMember sync {
    uint256 _amount = msg.value;
    address _member = msg.sender;
    _deposit(_member, _cycles, _amount);
  }

  /// @inheritdoc INatillera
  function addMember(address _member) external onlyOwner {
    _addMember(_member);
    _isMember[_member] = true;
    _members.push(_member);
  }

  /// --- VIEW FUNCTIONS ---

  /// @inheritdoc INatillera
  function members() external view returns (address[] memory) {
    return _members;
  }

  /// @inheritdoc INatillera
  function config() external view returns (NatilleraConfig memory) {
    return _config;
  }

  /// --- INTERNAL FUNCTIONS ---

  /**
   * @notice Deposits funds into the natillera
   * @param _member The member address of the member to deposit for
   * @param _cycles The number of cycles to deposit for
   * @param _amount The amount to deposit
   */
  function _deposit(address _member, uint256 _cycles, uint256 _amount) internal {
    if (_amount != _config.cuotaPorMes * _cycles) revert Natillera_InvalidDeposit();
    (, uint256 _amountDue,) = _trackContribution(_member);
    if (_amount > _amountDue) revert Natillera_OverPayment();
    bool _upToDate = _amountDue == _amount;
    _deposits[_member] += _amount;
    emit Deposit(_member, _amount, _upToDate);
  }

  /**
   * @notice Adds a member to the natillera
   * @param _member The wallet address to add
   */
  function _addMember(address _member) internal {
    IPlatform(PLATFORM).addMemberToProject(uuid, _member);
  }

  /**
   * @notice Syncs the cycle to the current cycle
   * @dev On initialization, cycle is set to 1
   */
  function _syncCycle() internal {
    if (block.timestamp > cycleDueDate + MES) {
      uint256 _currentCycle = (block.timestamp - _init) / MES;
      cycle = _currentCycle;
      cycleDueDate = _init + (MES * _currentCycle);
    }
  }

  /**
   * @notice Tracks the contribution of a member
   * @param _member The wallet address to track the contribution of
   * @return _amountPaid The amount paid for the contribution
   * @return _amountDue The amount due for the contribution
   * @return _missedCycles The number of missed cycles for a member
   */
  function _trackContribution(address _member)
    internal
    view
    returns (uint256 _amountPaid, uint256 _amountDue, uint256 _missedCycles)
  {
    uint256 cuotaPorMes = _config.cuotaPorMes;
    _amountDue = cuotaPorMes * cycle;
    _amountPaid = _deposits[_member];
    _amountDue -= _amountPaid;
    if (_amountDue > 0) _missedCycles = _amountDue / cuotaPorMes;
  }
}
