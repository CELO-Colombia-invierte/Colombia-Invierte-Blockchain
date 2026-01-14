pragma solidity 0.8.30;

import {IPlatform} from 'interfaces/IPlatform.sol';
import {ITracking} from 'interfaces/ITracking.sol';

/**
 * @title Natillera Contract
 * @author K-Labs
 * @notice This is a contract for the natillera of a project
 */
interface INatillera is ITracking {
  /*///////////////////////////////////////////////////////////////
                            DATA STRUCTS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice NatilleraConfig struct set by the creator of the natillera
   * @param token The token of the natillera (if native token, address(0))
   * @param cuotaPorMes The monthly contribution per month per member
   * @param cantidadDeMeses The number of months of the contribution period (30 dias por cada mes)
   * @param primerFechaDePago
   */
  struct NatilleraConfig {
    address token;
    uint256 cuotaPorMes;
    uint256 cantidadDeMeses;
    uint256 primerFechaDePago;
  }

  /*///////////////////////////////////////////////////////////////
                            LOGIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Initializes the natillera
   * @param _comienzo The start timestamp of the natillera
   * @param _config The configuration of the natillera
   * @param _govConfig The governance configuration for the natillera
   * @param _projectConfig The project configuration for the natillera
   */
  function initialize(uint256 _comienzo, NatilleraConfig calldata _config, IPlatform.GovernanceConfig calldata _govConfig, IPlatform.ProjectConfig calldata _projectConfig) external;

  /*///////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Returns the start timestamp of the natillera (primer fecha de pago)
   * @return _comienzo The timestamp to start the contribution period
   */
  function COMIENZO() external view returns (uint256 _comienzo);

  /**
   * @notice Returns the configuration of the natillera
   * @return _config The configuration of the natillera
   */
  function config() external view returns (NatilleraConfig _config);
}