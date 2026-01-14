// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from '@openzeppelin/contracts/proxy/utils/Initializable.sol';
import {INatillera} from 'interfaces/INatillera.sol';
import {IPlatform} from 'interfaces/IPlatform.sol';
import {Tracking} from 'contracts/Tracking.sol';

uint256 constant MES = 30 days;

contract Natillera is Initializable, Tracking, INatillera {
  /// @notice Project configuration
  NatilleraConfig internal _config;

  /// @inheritdoc INatillera
  function initialize(
    uint256 _comienzo,
    NatilleraConfig calldata _implConfig,
    IPlatform.GovernanceConfig calldata _govConfig,
    IPlatform.ProjectConfig calldata _projectConfig)
    external initializer {
    (uint256 _uuid, address _creator, address _platform) = (_projectConfig.uuid, _projectConfig.creator, _projectConfig.platform);
    uuid = _uuid;
    _config = _implConfig;
  }

  /// --- LOGIC FUNCTIONS ---

  function deposit() external payable {
    // TODO: Implement deposit logic
    // enforce equals cuota por mes
    // enforce payment recieved before fecha maxima de pago
    
  }
}