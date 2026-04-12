// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IRevenueModuleV2
 * @notice Interface for the revenue module managing investment, refunds, and reward distribution.
 * @author Key Lab Technical Team.
 */
interface IRevenueModuleV2 {
  /*//////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  struct InitParams {
    address token;
    address vault;
    address settlementToken;
    uint256 fundingTarget;
    uint256 minimumCap;
    uint256 tokenPrice;
    uint256 saleStart;
    uint256 saleEnd;
    uint256 distributionEnd;
    uint16 expectedApy;
    address governance;
    address projectCreator;
    address feeManager;
  }

  /*//////////////////////////////////////////////////////////////
                              ENUMS
  //////////////////////////////////////////////////////////////*/

  enum State {
    Pending,
    Active,
    Successful,
    Failed
  }

  /*//////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  error SaleClosed();
  error FundingTargetReached();
  error ZeroAmount();
  error DistributionEnded();
  error NothingToClaim();
  error Unauthorized();
  error InvalidState();
  error VaultPaused();
  error InvalidVaultState();
  error BelowMinimumCap();
  error InvalidAmount();

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  event Invested(address indexed investor, uint256 amount, uint256 tokensMinted);
  event RevenueDeposited(uint256 amount);
  event Claimed(address indexed user, uint256 amount);
  event SaleFinalized();
  event Refunded(address indexed user, uint256 amount);
  event SaleFailed();

  /*//////////////////////////////////////////////////////////////
                              CORE
  //////////////////////////////////////////////////////////////*/

  function initialize(InitParams calldata params) external;

  function state() external view returns (State);

  function invest(uint256 amount) external;

  function getMaxInvestable(uint256 amount) external view returns (uint256 validAmount, uint256 remainder);

  function finalizeSale() external;

  function refund() external;

  function depositRevenue(uint256 amount) external;

  function claim() external;

  function pending(address user) external view returns (uint256);

  function beforeTokenTransfer(address from, address to, uint256 amount) external;

  function updatePool() external;

  function finalizeFailure() external;

  function saleFinalized() external view returns (bool);

  function isStakeholder(address user) external view returns (bool);
}
