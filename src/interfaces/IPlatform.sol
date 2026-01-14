// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INatillera} from 'interfaces/INatillera.sol';

/**
 * @title Platform Contract
 * @author K-Labs
 * @notice This is a factory and fee collection contract for the platform
 */
interface IPlatform {
  /*///////////////////////////////////////////////////////////////
                            DATA STRUCTS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice PlatformParams of the contract
   * @param feeDeNatillera The deployment fee for the natillera: flat fee in native token
   * @param feeDeTokenizacion The deployment fee for the tokenizacion: percentage fee of value of the tokenization
   * @param feeDeWithdrawal The withdrawal fee: percentage fee of the withdrawal amount
   * @param delayMinimo The minimum delay for the governance execution
   * @param quorumMinimo The minimum quorum for the governance
   */
  struct PlatformParams {
    uint256 feeDeNatillera;
    uint256 feeDeTokenizacion;
    uint256 feeDeWithdrawal;
    uint256 delayMinimo;
    uint256 quorumMinimo;
  }

  /**
   * @notice GovernanceConfig struct for clone deployments
   * @param delayDeGobierno The delay for the governance execution
   * @param quorumMinimo The minimum quorum for the governance
   */
  struct GovernanceConfig {
    uint256 delayDeGobierno;
    uint256 quorumMinimo;
  }

  /**
   * @notice ProjectConfig struct for project deployment
   * @param uuid The uuid of the project
   * @param creator The creator of the project
   * @param platform The platform of the project
   */
  struct ProjectConfig {
    uint256 uuid;
    address creator;
    address platform;
  }


  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Event emitted when the natillera is deployed
   * @param _natillera The address of the deployed natillera
   * @param _id The id of the natillera
   */
  event DeployNatillera(address indexed _natillera, uint256 indexed _id);

  /**
   * @notice Event emitted when the tokenizacion is deployed
   * @param _tokenizacion The address of the deployed tokenizacion
   * @param _id The id of the tokenizacion
   */
  event DeployTokenizacion(address indexed _tokenizacion, uint256 indexed _id);

  /**
   * @notice Event emitted when a token is allowed or disallowed
   * @param _token The token that was allowed or disallowed
   * @param _allowed True if the token is allowed, false otherwise
   */
  event UpdateToken(address indexed _token, bool indexed _allowed);

  /**
   * @notice Event emitted when the parameters are set
   * @param _parameter The parameter that was set
   * @param _value The value that was set
   */
  event ParametersSet(bytes32 indexed _parameter, uint256 indexed _value);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice Error emitted when the parameter is invalid
  error Platform_InvalidParameter();
  /// @notice Error emitted when the token is invalid
  error Platform_InvalidToken();
  /// @notice Error emitted when the balance is zero
  error Platform_BalanceZero();
  /// @notice Error emitted when the deployment fee is insufficient
  error Platform_InsufficientFee();
  /// @notice Error emitted when the token is already registered
  error Platform_RegistryError();

  /*///////////////////////////////////////////////////////////////
                            LOGIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Deploys a new natillera
   * @param _natConfig The configuration of the natillera
   * @param _govConfig The governance configuration
   */
  function deployNatillera(INatillera.NatilleraConfig memory _natConfig, GovernanceConfig memory _govConfig) external payable;

  /**
   * @notice Deploys a new tokenizacion
   * @param _tokenConfig The configuration of the tokenizacion
   * @param _govConfig The governance configuration
   */
  function deployTokenizacion(TokenizacionParams memory _tokenConfig, GovernanceConfig memory _govConfig) external;

  /*///////////////////////////////////////////////////////////////
                            ACCESS CONTROL FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Withdraws the native fees
   */
  function withdrawNativeFees() external;

  /**
   * @notice Withdraws all fees
   */
  function withdrawERC20Fees() external;

  /**
   * @notice Withdraws the fees for a specific token
   * @param _token The token to withdraw the fees from
   */
  function withdrawERC20FeesPorToken(address _token) external;

  /**
   * @notice Add a token to the registry
   * @param _token The token to add to the registry
   */
  function addToken(address _token) external;

  /**
   * @notice Remove a token from the registry
   * @param _token The token to remove from the registry
   */
  function removeToken(address _token) external;

  /**
   * @notice Updates the parameters of the contract
   * @param _parameter The parameter to be updated (e.g. 'FEE_DE_NATILLERA')
   * @param _value The value to be set (e.g. 3000 for 3.0% fee)
   */
  function updateParameter(bytes32 _parameter, uint256 _value) external;

  /**
   * @notice Updates the implementation of the contract
   * @param _implementation The implementation to be updated
   * @param _type The type of the implementation (e.g. 'NATILLERA' or 'TOKENIZACION')
   */
  function updateImplementation(address _implementation, bytes32 _type) external;

  /*///////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Returns the implementation of the natillera
   * @return _implementation The current implementation address of the natillera
   */
  function natilleraImpl() external view returns (address _implementation);

  /**
   * @notice Returns the version of the natillera implementation
   * @return _version The current version of the natillera implementation
   */
  function natilleraVersion() external view returns (uint256 _version);

  /**
   * @notice Returns the implementation of the tokenizacion
   * @return _implementation The current implementation address of the tokenizacion
   */
  function tokenizacionImpl() external view returns (address _implementation);

  /**
   * @notice Returns the version of the tokenizacion implementation
   * @return _version The current version of the tokenizacion implementation
   */
  function tokenizacionVersion() external view returns (uint256 _version);

  /**
   * @notice Returns the parameters of the contract
   * @return _parameters The parameters of the contract
   */
  function parameters() external view returns (PlatformParams memory _parameters);

  /**
   * @notice Checks if a token is allowed
   * @param _token The token to check the status of
   * @return _allowed True if the token is allowed, false otherwise
   */
  function tokenStatus(address _token) external view returns (bool _allowed);

  /**
   * @notice Returns the proyecto by id
   * @param _id The id of the proyecto
   * @return _proyecto The address of the proyecto
   */
  function proyectoPorId(uint256 _id) external view returns (address _proyecto);

  /**
   * @notice Returns the usuario by wallet
   * @param _wallet The wallet to get the usuario of
   * @return _usuario The usuario of the wallet (usuario = keccak256 hash of the user email)
   */
  function walletDeUsuario(address _wallet) external view returns (bytes32 _usuario);

  /**
   * @notice Returns the ids by usuario
   * @param _usuario The usuario to get the ids of (usuario = keccak256 hash of the user email)
   * @return _ids The ids of the usuario
   */
  function idsPorUsuario(bytes32 _usuario) external view returns (uint256[] memory _ids);

  /**
   * @notice Returns the tokens
   * @return _tokens The tokens
   */
  function tokens() external view returns (address[] memory _tokens);

  /**
   * @notice Returns the balance of the treasury for a token
   * @param _token The token to get the balance of
   * @return _balance The balance of the token
   */
  function getBalancePorToken(address _token) external view returns (uint256 _balance);
}
