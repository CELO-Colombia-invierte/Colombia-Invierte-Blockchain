// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

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
   * @param feeDeNatillera The deployment fee for the natillera
   * @param feeDeTokenizacion The deployment fee for the tokenizacion
   * @param feeDeWithdrawal The withdrawal fee
   * @param delayDeGobierno The delay for the governance execution
   * @param quorumMinimo The minimum quorum for the governance
   */
  struct PlatformParams {
    uint256 feeDeNatillera;
    uint256 feeDeTokenizacion;
    uint256 feeDeWithdrawal;
    uint256 delayDeGobierno;
    uint256 quorumMinimo;
  }

  /**
   * @notice Implementation struct
   * @param implementation The address of the implementation
   * @param version The version of the implementation
   */
  struct Implementation {
    address implementation;
    bytes32 version;
  }

  /**
   * @notice NatilleraParams struct
   * @param id The id of the natillera
   * @param feeDeWithdrawal The withdrawal fee
   * @param delayDeGobierno The delay for the governance execution
   * @param quorumMinimo The minimum quorum for the governance
   * @param cuotaPorMes The monthly contribution per month per member
   * @param cantidadDeMeses The number of months of the contribution period
   * @param fechaMaximaDePago The maximum date of the contribution period every month
   */
  struct NatilleraParams {
    uint256 id;
    uint256 feeDeWithdrawal;
    uint256 delayDeGobierno;
    uint256 quorumMinimo;
    uint256 cuotaPorMes;
    uint256 cantidadDeMeses;
    uint256 fechaMaximaDePago;
    bytes32 version;
  }

  /**
   * @notice TokenizacionParams struct
   * @param id The id of the tokenizacion
   * @param delayDeGobierno The delay for the governance execution
   * @param quorumMinimo The minimum quorum for the governance
   */
  struct TokenizacionParams {
    uint256 id;
    uint256 delayDeGobierno;
    uint256 quorumMinimo;
    // TODO: Finalizar struct
    bytes32 version;
  }

  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /// @notice Event emitted when the natillera is deployed
  event DeployNatillera();
  /// @notice Event emitted when the tokenizacion is deployed
  event DeployTokenizacion();

  /**
   * @notice Event emitted when a token is allowed or disallowed
   * @param _token The token that was allowed or disallowed
   * @param _allowed True if the token is allowed, false otherwise
   */
  event UpdateToken(address _token, bool _allowed);

  /**
   * @notice Event emitted when the parameters are set
   * @param _parameter The parameter that was set
   * @param _value The value that was set
   */
  event ParametersSet(bytes32 _parameter, uint256 _value);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice Error emitted when the parameter is invalid
  error Platform_InvalidParameter();
  /// @notice Error emitted when the token is invalid
  error Platform_InvalidToken();
  /// @notice Error emitted when the balance is zero
  error Platform_BalanceZero();
  /// @notice Error emitted when the deployment failed
  error Platform_DeploymentFailed();

  /*///////////////////////////////////////////////////////////////
                            LOGIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Deploys a new natillera
   * @param _config The configuration of the natillera
   */
  function deployNatillera(NatilleraParams memory _config) external;

  /**
   * @notice Deploys a new tokenizacion
   * @param _config The configuration of the tokenizacion
   */
  function deployTokenizacion(TokenizacionParams memory _config) external;

  /*///////////////////////////////////////////////////////////////
                            ACCESS CONTROL FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Withdraws the fees for a specific token
   * @dev onlyOwner access control
   * @param _token The token to withdraw the fees from
   */
  function withdrawFeesPorToken(address _token) external;

  /**
   * @notice Withdraws all fees
   * @dev onlyOwner access control
   */
  function withdrawFees() external;

  /**
   * @notice Updates the status of a token
   * @dev onlyOwner access control
   * @param _token The token to be updated: true if allowed, false if disallowed
   */
  function updateToken(address _token, bool _allowed) external;

  /**
   * @notice Updates the parameters of the contract
   * @dev onlyOwner access control
   * @param _parameter The parameter to be updated (e.g. 'FEE_DE_NATILLERA')
   * @param _value The value to be set (e.g. 3000 for 3.0% fee)
   */
  function updateParameters(bytes32 _parameter, uint256 _value) external;

  /**
   * @notice Updates the implementation of the contract
   * @dev onlyOwner access control
   * @param _implementation The implementation to be updated
   * @param _version The version of the implementation
   * @param _type The type of the implementation (e.g. 'NATILLERA' or 'TOKENIZACION')
   */
  function updateImplementation(address _implementation, bytes32 _version, bytes32 _type) external;

  /*///////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/
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
   * @notice Returns the ids by usuario
   * @param _usuario The usuario to get the ids of
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
