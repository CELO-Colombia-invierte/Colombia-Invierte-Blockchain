// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IProjectVault
 * @notice Interface for the project vault that holds funds and enforces state transitions.
 * @author Key Lab Technical Team.
 */
interface IProjectVault {
  enum VaultState {
    Locked,
    Active,
    Closed
  }
  enum FundingModel {
    Natillera,
    Revenue
  }

  /*//////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  error ZeroAddress();
  error ZeroAmount();
  error InvalidState();
  error TokenNotAllowed();
  error InsufficientBalance();
  error Unauthorized();
  error VaultPaused();
  error InvalidVaultState();
  error InvalidModel();
  error CannotUnfreezeDispute();

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  event VaultInitialized(address indexed project, address indexed governance);
  event Deposited(address indexed token, address indexed from, uint256 amount);
  event Activated();
  event Closed();
  event Released(address indexed token, address indexed to, uint256 amount);
  event TokenAllowed(address indexed token, bool allowed);
  event FeesReserved(uint256 amount);
  event ReservedFeesConsumed(uint256 amount);
  event FrozenByDispute(uint256 indexed disputeId);
  event UnfrozenFromDispute();
  event YieldDeposited(address indexed token, address indexed from, uint256 amount);

  /*//////////////////////////////////////////////////////////////
                              CORE
  //////////////////////////////////////////////////////////////*/

  function initialize(
    address project_,
    address governance_,
    address guardian_,
    address allowedToken_,
    FundingModel model_
  ) external;

  function setTokenAllowed(address token, bool allowed) external;

  function depositFrom(address from, address token, uint256 amount) external;

  function depositYield(address from, address token, uint256 amount) external;

  function reserveFees(address token, uint256 amount) external;

  function consumeReservedFees(address token, uint256 amount) external;

  function activate() external;

  function release(address token, address to, uint256 amount) external;

  function releaseOnClose(address token, address to, uint256 amount) external;

  function close() external;

  /*//////////////////////////////////////////////////////////////
                              VIEW
  //////////////////////////////////////////////////////////////*/

  function state() external view returns (VaultState);

  function project() external view returns (address);

  function isTokenAllowed(address token) external view returns (bool);

  function reservedFees(address token) external view returns (uint256);

  function totalBalance(address token) external view returns (uint256);

  function model() external view returns (FundingModel);

  function availableBalance(address token) external view returns (uint256);

  /*//////////////////////////////////////////////////////////////
                              EMERGENCY
  //////////////////////////////////////////////////////////////*/

  function pause() external;

  function unpause() external;

  function paused() external view returns (bool);

  function freezeByDispute(uint256 disputeId) external;

  function unfreezeFromDispute() external;

  function activeDisputeId() external view returns (uint256);
}
