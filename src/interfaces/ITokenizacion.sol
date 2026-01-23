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
   * @notice TokenizacionParams struct for project configuration
   * @param token The payment token (ERC20 address or address(0) for native)
   * @param pricePerToken The price per token in wei (or token units)
   * @param totalTokens The total number of tokens available for sale
   * @param presaleEnabled Whether presale is enabled
   * @param presaleStartsAt Timestamp when presale starts (0 if disabled)
   * @param publicSaleStartsAt Timestamp when public sale starts (0 if disabled)
   */
  struct TokenizacionParams {
    address token;
    uint256 pricePerToken;
    uint256 totalTokens;
    bool presaleEnabled;
    uint256 presaleStartsAt;
    uint256 publicSaleStartsAt;
  }

  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Event emitted when tokens are purchased
   * @param _investor The address of the investor
   * @param _amount The amount of tokens purchased
   * @param _paymentAmount The amount paid for the tokens
   */
  event TokensPurchased(address indexed _investor, uint256 indexed _amount, uint256 indexed _paymentAmount);

  /**
   * @notice Event emitted when an investor is added
   * @param _investor The address of the investor
   */
  event InvestorAdded(address indexed _investor);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/
  /// @notice Error emitted when the sale is not active
  error Tokenizacion_SaleNotActive();
  /// @notice Error emitted when the payment amount is insufficient
  error Tokenizacion_InsufficientPayment();
  /// @notice Error emitted when there are not enough tokens available
  error Tokenizacion_InsufficientTokens();
  /// @notice Error emitted when the investor is not registered
  error Tokenizacion_NotInvestor();
  /// @notice Error emitted when trying to purchase zero tokens
  error Tokenizacion_InvalidAmount();
  /// @notice Error emitted when trying to use wrong payment method
  error Tokenizacion_InvalidPaymentMethod();
  /// @notice Error emitted when sale has not started yet
  error Tokenizacion_SaleNotStarted();
  /// @notice Error emitted when a transfer operation fails
  error Tokenizacion_TransferFailed();
  /// @notice Error emitted when configuration parameters are invalid
  error Tokenizacion_InvalidConfig();

  /*///////////////////////////////////////////////////////////////
                            LOGIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Initializes the tokenizacion
   * @param _config The configuration of the tokenizacion
   * @param _govConfig The governance configuration for the tokenizacion
   * @param _projectConfig The project configuration for the tokenizacion
   */
  function initialize(
    TokenizacionParams calldata _config,
    IPlatform.GovernanceConfig calldata _govConfig,
    IPlatform.ProjectConfig calldata _projectConfig
  ) external;

  /**
   * @notice Purchases tokens with native currency
   * @param _amount The amount of tokens to purchase
   */
  function purchaseTokens(uint256 _amount) external payable;

  /**
   * @notice Purchases tokens with ERC20 token
   * @param _amount The amount of tokens to purchase
   */
  function purchaseTokensWithERC20(uint256 _amount) external;

  /**
   * @notice Adds an investor to the project (presale access)
   * @param _investor The address of the investor to add
   */
  function addInvestor(address _investor) external;

  /*///////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Returns the configuration of the tokenizacion
   * @return _config The configuration
   */
  function config() external view returns (TokenizacionParams memory _config);

  /**
   * @notice Returns the list of investors
   * @return _investors The array of investor addresses
   */
  function investors() external view returns (address[] memory _investors);

  /**
   * @notice Returns the token balance of an investor
   * @param _investor The address of the investor
   * @return _balance The token balance
   */
  function balanceOf(address _investor) external view returns (uint256 _balance);

  /**
   * @notice Returns the total tokens sold
   * @return _sold The total tokens sold
   */
  function totalTokensSold() external view returns (uint256 _sold);

  /**
   * @notice Returns the total tokens available
   * @return _available The total tokens available
   */
  function totalTokensAvailable() external view returns (uint256 _available);

  /**
   * @notice Checks if an address is an investor
   * @param _investor The address to check
   * @return _isInvestor True if the address is an investor
   */
  function isInvestor(address _investor) external view returns (bool _isInvestor);

  /**
   * @notice Checks if presale is active
   * @return _isActive True if presale is active
   */
  function isPresaleActive() external view returns (bool _isActive);

  /**
   * @notice Checks if public sale is active
   * @return _isActive True if public sale is active
   */
  function isPublicSaleActive() external view returns (bool _isActive);

  /**
   * @notice Withdraws collected funds (native or ERC20)
   * @dev onlyOwner
   * @param _to The address to withdraw to
   */
  function withdrawFunds(address payable _to) external;

  /**
   * @notice Calculates the cost for a given amount of tokens
   * @param _amount The amount of tokens
   * @return _cost The cost in payment token
   */
  function cost(uint256 _amount) external view returns (uint256 _cost);

  /**
   * @notice Returns the remaining tokens available for purchase
   * @return _remaining The remaining tokens
   */
  function remainingTokens() external view returns (uint256 _remaining);
}
