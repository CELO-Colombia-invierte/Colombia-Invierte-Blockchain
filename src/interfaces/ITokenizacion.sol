pragma solidity 0.8.30;

import {IPlatform} from 'interfaces/IPlatform.sol';
import {ITracking} from 'interfaces/ITracking.sol';

/**
 * @title Tokenizacion Contract
 * @author K-Labs
 * @notice This is a contract for the tokenization of a project
 */
interface ITokenizacion is ITracking {
  /*///////////////////////////////////////////////////////////////
                            DATA STRUCTS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice TokenizacionParams struct
   * @param placeholder Placeholder for the tokenization parameters
   */
  struct TokenizacionParams {
    // TODO: Finalizar struct
    uint256 placeholder;
  }

  /*///////////////////////////////////////////////////////////////
                            LOGIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Initializes the tokenizacion
   * @param _config The configuration of the tokenizacion
   * @param _govConfig The governance configuration for the tokenizacion
   * @param _projectConfig The project configuration for the tokenizacion
   */
  function initialize(TokenizacionParams calldata _config, IPlatform.GovernanceConfig calldata _govConfig, IPlatform.ProjectConfig calldata _projectConfig) external;

  /*///////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/
}