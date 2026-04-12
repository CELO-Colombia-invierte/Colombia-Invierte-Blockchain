// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title ITokenizacion
 * @notice Interface for token sale projects
 * @dev MVP V1: Simple token sale with fixed price
 */
interface ITokenizacion {
  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Sale configuration structure
   * @param paymentToken ERC20 token for payment (address(0) for native ETH)
   * @param pricePerToken Price per project token (in payment token decimals)
   * @param totalTokens Total tokens available for sale (in token units)
   * @param saleStart Timestamp when the sale starts
   * @param saleDuration Sale duration in seconds
   */
  struct Config {
    address paymentToken;
    uint256 pricePerToken;
    uint256 totalTokens;
    uint256 saleStart;
    uint256 saleDuration;
  }

  /**
   * @notice Project information structure
   * @param platform Platform contract address
   * @param projectId Unique project identifier
   * @param creator Project creator address
   */
  struct ProjectInfo {
    address platform;
    uint256 projectId;
    address creator;
  }

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice Error emitted when trying to buy tokens while sale is inactive
  error SaleNotActive();
  /// @notice Error emitted when trying to purchase more tokens than available
  error InsufficientTokens();
  /// @notice Error emitted when trying to interact with a finalized sale
  error SaleEnded();
  /// @notice Error emitted when non-creator tries to perform creator-only actions
  error NotCreator();
  /// @notice Error emitted when invalid payment amount or token is provided
  error InvalidPayment();
  /// @notice Error emitted when trying to initialize an already initialized sale
  error AlreadyInitialized();

  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Event emitted when tokens are purchased
   * @param buyer Address of the token purchaser
   * @param tokens Number of tokens purchased
   * @param paid Amount paid for the tokens (in payment token decimals)
   * @dev Emitted from `buyTokens()` function
   */
  event TokensPurchased(address indexed buyer, uint256 tokens, uint256 paid);

  /**
   * @notice Event emitted when the sale is finalized
   * @param totalSold Total number of tokens sold
   * @dev Emitted from `finalizeSale()` function
   */
  event SaleFinalized(uint256 totalSold);

  /**
   * @notice Event emitted when funds are withdrawn by the creator
   * @param recipient Address that received the funds
   * @param amount Amount withdrawn (in payment token decimals)
   * @dev Emitted from `withdrawFunds()` function
   */
  event FundsWithdrawn(address recipient, uint256 amount);

  /*///////////////////////////////////////////////////////////////
                          INITIALIZATION
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Initialize the token sale with configuration and project info
   * @param config_ Sale configuration parameters
   * @param info_ Project information
   * @dev Can only be called once per contract instance
   */
  function initialize(Config calldata config_, ProjectInfo calldata info_) external;

  /*///////////////////////////////////////////////////////////////
                          CORE FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Purchase tokens from the sale
   * @param amount Number of tokens to purchase (in token units)
   * @dev Accepts either ETH (if paymentToken is address(0)) or ERC20 tokens
   * @dev Requires exact payment amount: amount * pricePerToken
   */
  function buyTokens(uint256 amount) external payable;

  /**
   * @notice Finalize the token sale
   * @dev Can be called by creator to manually finalize before sale end
   * @dev Disables further token purchases
   */
  function finalizeSale() external;

  /**
   * @notice Withdraw collected funds to the creator
   * @dev Can only be called after sale is finalized
   * @dev Transfers all collected funds to the creator address
   */
  function withdrawFunds() external;

  /*///////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Get the sale configuration
   * @return Config memory Sale configuration structure
   */
  function config() external view returns (Config memory);

  /**
   * @notice Get total number of tokens sold
   * @return uint256 Total tokens sold so far
   */
  function tokensSold() external view returns (uint256);

  /**
   * @notice Get total funds collected
   * @return uint256 Total funds collected (in payment token decimals)
   */
  function fundsCollected() external view returns (uint256);

  /**
   * @notice Check if sale is currently active
   * @return bool True if sale is active, false otherwise
   * @dev Sale is active if: not finalized, within sale period, and tokens remain
   */
  function isSaleActive() external view returns (bool);

  /**
   * @notice Get remaining tokens available for purchase
   * @return uint256 Number of tokens still available in the sale
   */
  function remainingTokens() external view returns (uint256);

  /**
   * @notice Get project information
   * @return ProjectInfo memory Project information structure
   */
  function projectInfo() external view returns (ProjectInfo memory);
}
