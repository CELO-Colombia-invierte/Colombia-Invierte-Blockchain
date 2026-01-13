// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable, Ownable2Step} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';
import {IERC20, SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IPlatform} from 'interfaces/IPlatform.sol';

contract Platform is IPlatform, Ownable2Step {
  using SafeERC20 for IERC20;

  /// @inheritdoc IPlatform
  address public natilleraImpl;
  /// @inheritdoc IPlatform
  uint256 public natilleraVersion;
  /// @inheritdoc IPlatform
  address public tokenizacionImpl;
  /// @inheritdoc IPlatform
  uint256 public tokenizacionVersion;

  /// @inheritdoc IPlatform
  mapping(address _token => bool _allowed) public tokenStatus;
  /// @inheritdoc IPlatform
  mapping(uint256 _id => address _proyecto) public proyectoPorId;
  /// @notice Mapping of user to their project IDs
  mapping(bytes32 _usuario => uint256[] _ids) internal _idsPorUsuario;

  /// @notice The unique project identifier
  uint256 internal _uid;

  /// @notice The parameters of the platform
  PlatformParams internal _pps;

  /// @notice Array of allowed tokens
  address[] internal _registeredTokens;

  /**
   * @notice Modifier to verify the governance configuration
   * @param _config The governance configuration to verify
   */
  modifier verifyConfig(GovernanceConfig memory _config) {
    if (_config.delayDeGobierno < _pps.delayMinimo) revert Platform_InvalidParameter();
    if (_config.quorumMinimo < _pps.quorumMinimo) revert Platform_InvalidParameter();
    _;
  }

  modifier verifyToken(address _token) {
    if (!_tokenExists(_token)) revert Platform_InvalidToken();
    _;
  }

  /**
   * @notice Constructor of the contract
   * @param _initialOwner The initial owner of the contract
   * @param _natilleraImpl The implementation address of the natillera
   * @param _tokenizacionImpl The implementation address of the tokenizacion
   * @param _platformParams The parameters of the platform
   */
  constructor(
    address _initialOwner,
    address _natilleraImpl,
    address _tokenizacionImpl,
    PlatformParams memory _platformParams
  ) Ownable(_initialOwner) {
    _pps = _platformParams;
    natilleraImpl = _natilleraImpl;
    tokenizacionImpl = _tokenizacionImpl;
    natilleraVersion = 1;
    tokenizacionVersion = 1;
  }

  /// --- LOGIC FUNCTIONS ---

  /// @inheritdoc IPlatform
  function deployNatillera(
    NatilleraConfig memory _config,
    GovernanceConfig memory _govConfig
  ) external payable verifyConfig(_govConfig) {
    if (msg.value < _pps.feeDeNatillera) revert Platform_InsufficientFee();
    ++_uid;
    address clone = Clones.clone(natilleraImpl);
    // INatillera(clone).initialize(_config, _govConfig, _uid, msg.sender, address(this));
    proyectoPorId[_uid] = clone;
    emit DeployNatillera(clone, _uid);
  }

  /// @inheritdoc IPlatform
  function deployTokenizacion(
    TokenizacionParams memory _config,
    GovernanceConfig memory _govConfig
  ) external verifyConfig(_govConfig) {
    // TODO: implement percentage fee for the tokenization
    ++_uid;
    address clone = Clones.clone(tokenizacionImpl);
    // ITokenizacion(clone).initialize(_config, _govConfig, _uid, msg.sender, address(this));
    proyectoPorId[_uid] = clone;
    emit DeployTokenizacion(clone, _uid);
  }

  /// --- ACCESS CONTROL FUNCTIONS ---

  /// @inheritdoc IPlatform
  function withdrawNativeFees() external onlyOwner {
    if (address(this).balance == 0) revert Platform_BalanceZero();
    payable(owner()).transfer(address(this).balance);
  }

  /// @inheritdoc IPlatform
  function withdrawERC20Fees() external onlyOwner {
    uint256 _l = _registeredTokens.length;
    for (uint256 i = 0; i < _l; i++) {
      address _token = _registeredTokens[i];
      if (_balanceGTZero(_token)) {
        _withdrawFeesPorToken(_token);
      }
    }
  }

  /// @inheritdoc IPlatform
  function withdrawERC20FeesPorToken(address _token) external onlyOwner {
    if (!_balanceGTZero(_token)) revert Platform_BalanceZero();
    _withdrawFeesPorToken(_token);
  }

  /// @inheritdoc IPlatform
  function addToken(address _token) external onlyOwner verifyToken(_token) {
    if (tokenStatus[_token]) revert Platform_RegistryError();
    tokenStatus[_token] = true;
    _registeredTokens.push(_token);
    emit UpdateToken(_token, true);
  }

  /// @inheritdoc IPlatform
  function removeToken(address _token) external onlyOwner verifyToken(_token) {
    if (!tokenStatus[_token]) revert Platform_RegistryError();
    tokenStatus[_token] = false;
    _removeTokenFromRegistry(_token);
    emit UpdateToken(_token, false);
  }

  /// @inheritdoc IPlatform
  function updateParameter(bytes32 _parameter, uint256 _value) external onlyOwner {
    if (_parameter == 'FEE_DE_NATILLERA') _pps.feeDeNatillera = _value;
    else if (_parameter == 'FEE_DE_TOKENIZACION') _pps.feeDeTokenizacion = _value;
    else if (_parameter == 'FEE_DE_WITHDRAWAL') _pps.feeDeWithdrawal = _value;
    else if (_parameter == 'DELAY_MINIMO') _pps.delayMinimo = _value;
    else if (_parameter == 'QUORUM_MINIMO') _pps.quorumMinimo = _value;
    else revert Platform_InvalidParameter();
  }

  /// @inheritdoc IPlatform
  function updateImplementation(address _implementation, bytes32 _type) external onlyOwner {
    _setImplementation(_implementation, _type);
  }

  /// --- VIEW FUNCTIONS ---

  /// @inheritdoc IPlatform
  function parameters() external view returns (PlatformParams memory _params) {
    return _pps;
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
   * @param _type The type of the implementation (e.g. 'NATILLERA' or 'TOKENIZACION')
   */
  function _setImplementation(address _implementation, bytes32 _type) internal {
    if (_type == 'NATILLERA') {
      natilleraImpl = _implementation;
      ++natilleraVersion;
    } else if (_type == 'TOKENIZACION') {
      tokenizacionImpl = _implementation;
      ++tokenizacionVersion;
    } else {
      revert Platform_InvalidParameter();
    }
  }

  /**
   * @notice Removes a token from the registered tokens
   * @param _token The token to remove
   */
  function _removeTokenFromRegistry(address _token) internal {
    uint256 _l = _registeredTokens.length;
    for (uint256 i = 0; i < _l; i++) {
      if (_registeredTokens[i] == _token) {
        _registeredTokens[i] = _registeredTokens[_l - 1];
        _registeredTokens.pop();
        break;
      }
    }
  }

  /**
   * @notice Checks if a token exists
   * @param _token The token to check the existence of
   * @return _exists True if the token exists, false otherwise
   */
  function _tokenExists(address _token) internal view returns (bool _exists) {
    _exists = IERC20(_token).totalSupply() > 0;
  }

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
}
