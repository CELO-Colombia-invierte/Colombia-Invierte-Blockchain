// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable, Ownable2Step} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {IERC20, SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IPlatform} from 'interfaces/IPlatform.sol';

contract Platform is IPlatform, Ownable2Step {
  using SafeERC20 for IERC20;

  /// @inheritdoc IPlatform
  mapping(address _token => bool _allowed) public tokenStatus;
  /// @inheritdoc IPlatform
  mapping(uint256 _id => address _proyecto) public proyectoPorId;
  /// @notice Mapping of user to their project IDs
  mapping(bytes32 _usuario => uint256[] _ids) internal _idsPorUsuario;

  /// @notice The parameters of the platform
  PlatformParams internal _platformParams;
  /// @notice The implementation of the natillera for clone deployment
  Implementation internal _natilleraImpl;
  /// @notice The implementation of the tokenizacion for clone deployment
  Implementation internal _tokenizacionImpl;

  /// @notice Array of allowed tokens
  address[] internal _registeredTokens;

  constructor(
    address _initialOwner,
    address __natilleraImpl,
    address __tokenizacionImpl,
    PlatformParams memory _params
  ) Ownable(_initialOwner) {
    _platformParams = _params;
    _setImplementation(__natilleraImpl, 'v1.0.0', 'NATILLERA');
    _setImplementation(__tokenizacionImpl, 'v1.0.0', 'TOKENIZACION');
  }

  /// --- LOGIC FUNCTIONS ---

  /// @inheritdoc IPlatform
  function deployNatillera(NatilleraParams memory _config) external {
    // TODO: implement
  }

  /// @inheritdoc IPlatform
  function deployTokenizacion(TokenizacionParams memory _config) external {
    // TODO: implement
  }

  /// --- ACCESS CONTROL FUNCTIONS ---

  /// @inheritdoc IPlatform
  function withdrawFeesPorToken(address _token) external onlyOwner {
    if (!_balanceGTZero(_token)) revert Platform_BalanceZero();
    _withdrawFeesPorToken(_token);
  }

  /// @inheritdoc IPlatform
  function withdrawFees() external onlyOwner {
    uint256 _l = _registeredTokens.length;
    for (uint256 i = 0; i < _l; i++) {
      address _token = _registeredTokens[i];
      if (_balanceGTZero(_token)) {
        _withdrawFeesPorToken(_token);
      }
    }
  }

  /// @inheritdoc IPlatform
  function updateToken(address _token, bool _allowed) external onlyOwner {
    if (IERC20(_token).totalSupply() == 0) revert Platform_InvalidToken();
    tokenStatus[_token] = _allowed;
    emit UpdateToken(_token, _allowed);
  }

  /// @inheritdoc IPlatform
  function updateParameters(bytes32 _parameter, uint256 _value) external onlyOwner {
    if (_parameter == 'FEE_DE_NATILLERA') _platformParams.feeDeNatillera = _value;
    else if (_parameter == 'FEE_DE_TOKENIZACION') _platformParams.feeDeTokenizacion = _value;
    else if (_parameter == 'FEE_DE_WITHDRAWAL') _platformParams.feeDeWithdrawal = _value;
    else if (_parameter == 'DELAY_DE_GOBIERNO') _platformParams.delayDeGobierno = _value;
    else if (_parameter == 'QUORUM_MINIMO') _platformParams.quorumMinimo = _value;
    else revert Platform_InvalidParameter();
  }

  /// @inheritdoc IPlatform
  function updateImplementation(address _implementation, bytes32 _version, bytes32 _type) external onlyOwner {
    _setImplementation(_implementation, _version, _type);
  }

  /// --- VIEW FUNCTIONS ---

  /// @inheritdoc IPlatform
  function parameters() external view returns (PlatformParams memory _params) {
    return _platformParams;
  }

  /// @inheritdoc IPlatform
  function tokens() external view returns (address[] memory _tokens) {
    _tokens = _registeredTokens;
  }

  /// @inheritdoc IPlatform
  function getBalancePorToken(address _token) external view returns (uint256 _balance) {
    return _getBalancePorToken(_token);
  }

  /// @inheritdoc IPlatform
  function idsPorUsuario(bytes32 _usuario) external view returns (uint256[] memory _ids) {
    return _idsPorUsuario[_usuario];
  }

  /// --- INTERNAL FUNCTIONS ---

  /**
   * @notice Gets the balance of a token
   * @param _token The token to get the balance of
   * @return _balance The balance of the token
   */
  function _getBalancePorToken(address _token) internal view returns (uint256 _balance) {
    _balance = IERC20(_token).balanceOf(address(this));
  }

  /**
   * @notice Checks if the balance of a token is greater than zero
   * @param _token The token to check the balance of
   * @return _isGTZero True if the balance is greater than zero, false otherwise
   */
  function _balanceGTZero(address _token) internal view returns (bool _isGTZero) {
    _isGTZero = _getBalancePorToken(_token) > 0;
  }

  /**
   * @notice Withdraws the fees for a specific token
   * @param _token The token to withdraw the fees from
   */
  function _withdrawFeesPorToken(address _token) internal {
    uint256 _amount = _getBalancePorToken(_token);
    IERC20(_token).safeTransfer(owner(), _amount);
  }

  /**
   * @notice Sets the implementation of the contract
   * @param _implementation The implementation to be set
   * @param _version The version of the implementation
   * @param _type The type of the implementation (e.g. 'NATILLERA' or 'TOKENIZACION')
   */
  function _setImplementation(address _implementation, bytes32 _version, bytes32 _type) internal {
    if (_type == 'NATILLERA') _natilleraImpl = Implementation(_implementation, _version);
    else if (_type == 'TOKENIZACION') _tokenizacionImpl = Implementation(_implementation, _version);
    else revert Platform_InvalidParameter();
  }
}
