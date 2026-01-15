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
   */
  struct NatilleraConfig {
    address token;
    uint256 cuotaPorMes;
    uint256 cantidadDeMeses;
  }

  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Event emitted when a deposit is made
   * @param _member The member address of the member who made the deposit
   * @param _amount The amount of the deposit
   * @param _upToDate True if the deposit is up to date, false otherwise
   */
  event Deposit(address indexed _member, uint256 indexed _amount, bool indexed _upToDate);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice Error emitted when the deposit does not match the contribution amount
  error Natillera_InvalidDeposit();
  /// @notice Error emitted when the payment submitted is over the amount due
  error Natillera_OverPayment();
  /// @notice Error emitted when the member is not a member of the natillera
  error Natillera_NotMember();

  /*///////////////////////////////////////////////////////////////
                            LOGIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Initializes the natillera
   * @param _comienzo The start timestamp of the natillera (due date of the first cycle/payment)
   * @param _config The configuration of the natillera
   * @param _govConfig The governance configuration for the natillera
   * @param _projectConfig The project configuration for the natillera
   */
  function initialize(
    uint256 _comienzo,
    NatilleraConfig calldata _config,
    IPlatform.GovernanceConfig calldata _govConfig,
    IPlatform.ProjectConfig calldata _projectConfig
  ) external;

  /**
   * @notice Tracks the contribution of a member
   * @param _member The member address of the member to track the contribution of
   * @return _amountPaid The amount paid for the contribution
   * @return _amountDue The amount due for the contribution
   * @return _missedCycles The number of missed cycles for the contribution
   */
  function trackContribution(address _member)
    external
    returns (uint256 _amountPaid, uint256 _amountDue, uint256 _missedCycles);

  /*///////////////////////////////////////////////////////////////
                            ACCESS CONTROL FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Deposits funds into the natillera for the current month
   * @dev payable
   */
  function depositSingleCycle() external payable;

  /**
   * @notice Deposits funds into the natillera for a past due cycle
   * @dev payable
   * @param _cycles The number of cycles to deposit for
   */
  function depositMultipleCycles(uint256 _cycles) external payable;

  /**
   * @notice Adds a member to the natillera by id
   * @dev onlyOwner
   * @param _member The member address to add
   */
  function addMember(address _member) external;

  /*///////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Returns the cycle of the natillera
   * @return _cycle The cycle of the natillera
   */
  function cycle() external view returns (uint256 _cycle);

  /**
   * @notice Returns the due date of the current cycle
   * @return _cycleDueDate The due date of the current cycle
   */
  function cycleDueDate() external view returns (uint256 _cycleDueDate);

  /**
   * @notice Returns the members of the natillera
   * @return _members The members of the natillera
   */
  function members() external view returns (address[] memory _members);

  /**
   * @notice Returns the configuration of the natillera
   * @return _config The configuration of the natillera
   */
  function config() external view returns (NatilleraConfig memory _config);
}
