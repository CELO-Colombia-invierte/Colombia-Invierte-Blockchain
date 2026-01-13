// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from 'forge-std/interfaces/IERC20.sol';
import {IPlatform} from 'interfaces/IPlatform.sol';

// TODO: inherit ownable
contract Platform is IPlatform {
  /// @inheritdoc IPlatform
  Parameters public parameters;

  /// @inheritdoc IPlatform
  mapping(address _token => bool _allowed) public tokenStatus;

  /// @inheritdoc IPlatform
  mapping(uint256 _id => address _proyecto) public proyectoPorId;

  /// @inheritdoc IPlatform
  mapping(bytes32 _usuario => uint256[] _ids) public idsPorUsuario;

  constructor(Parameters memory _parameters) {
    parameters = _parameters;
  }

  /// @inheritdoc IPlatform
  function deployNatillera(Natillera memory _config) external;

  /// @inheritdoc IPlatform
  function deployTokenizacion(Tokenizacion memory _config) external;

  /// @inheritdoc IPlatform
  function withdrawFees(uint256 _cantidad) external;

  /// @inheritdoc IPlatform
  function withdrawTodoDeFees() external;

  /// @inheritdoc IPlatform
  function updateToken(address _token, bool _allowed) external {
    if (!IERC20(_token).totalSupply() > 0) revert Platform_InvalidToken();
    tokenStatus[_token] = _allowed;
    emit UpdateToken(_token, _allowed);
  }

  /// @inheritdoc IPlatform
  function updateParameters(bytes32 _parameter, uint256 _value) external {
    if (_parameter == 'FEE_DE_NATILLERA') parameters.feeDeNatillera = _value;
    else if (_parameter == 'FEE_DE_TOKENIZACION') parameters.feeDeTokenizacion = _value;
    else if (_parameter == 'FEE_DE_WITHDRAWAL') parameters.feeDeWithdrawal = _value;
    else if (_parameter == 'DELAY_DE_GOBIERNO') parameters.delayDeGobierno = _value;
    else if (_parameter == 'QUORUM_MINIMO') parameters.quorumMinimo = _value;
    else revert Platform_InvalidParameter();
  }
}
