// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import {IERC20, SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import {Tracking} from 'contracts/Tracking.sol';
import {ITokenizacion} from 'interfaces/ITokenizacion.sol';
import {IPlatform} from 'interfaces/IPlatform.sol';

/**
 * @title Tokenizacion Contract
 * @notice This contract manages the sale of project tokens (not ERC20 tokens).
 *         Tokens are represented as internal balances tracked in a mapping.
 *         This is NOT an ERC20 token contract - it's a token sale mechanism.
 *         Investors purchase "shares" or "positions" in a project, tracked as balances.
 * @dev The balanceOf function returns internal balances, not ERC20 balances.
 *      There is no minting, transfer, or supply mechanism - only purchase tracking.
 * 
 * @dev DESIGN DECISIONS:
 *      - Balances are IMMUTABLE: No transfer, burn, or redeem functions exist.
 *        These tokens represent future rights/claims that may require:
 *        * claim() - to claim rewards/distributions
 *        * redeem() - to redeem tokens for underlying assets
 *        * convertToERC20() - to convert to transferable ERC20 tokens
 *        These functions are NOT implemented in this version but may be added later.
 * 
 *      - Price is IMMUTABLE: pricePerToken is set at initialization and cannot be changed.
 *        If future versions require:
 *        * Multiple pricing rounds
 *        * Tiered pricing
 *        * Governance-controlled price changes
 *        Then setters with timelock/governance will be needed.
 */
contract Tokenizacion is Initializable, Tracking, OwnableUpgradeable, ReentrancyGuardUpgradeable, ITokenizacion {
  using SafeERC20 for IERC20;

  /// @notice Project configuration
  TokenizacionParams internal _config;

  /// @notice Internal balances of purchased tokens (NOT ERC20 balances)
  /// @dev These represent "shares" or "positions" in the project, not transferable tokens
  mapping(address _investor => uint256 _balance) internal _balances;

  /// @notice Whether an address is an investor (for presale access/whitelist)
  mapping(address _wallet => bool _investor) internal _isInvestor;

  /// @notice List of all investors (whitelisted + buyers)
  /// @dev NOTE: _investors contains both whitelisted investors (via addInvestor) 
  ///      and buyers (added on first purchase). Each address is pushed at most once.
  ///      This array grows unbounded - prefer events for off-chain indexing in production.
  address[] internal _investors;

  /// @notice Total tokens sold
  uint256 internal _totalSold;

  /// @notice Modifier to verify investor status for presale
  /// @dev Currently unused but reserved for future governance functions
  ///      that may require whitelist access (e.g., voting, claiming)
  modifier onlyInvestor() {
    if (!_isInvestor[msg.sender]) revert Tokenizacion_NotInvestor();
    _;
  }

  /// @notice Modifier to verify sale is active
  modifier saleActive() {
    if (!_isSaleActive()) revert Tokenizacion_SaleNotActive();
    _;
  }

  /// @inheritdoc ITokenizacion
  function initialize(
    TokenizacionParams calldata _implConfig,
    IPlatform.GovernanceConfig calldata _govConfig,
    IPlatform.ProjectConfig calldata _projectConfig
  ) external initializer {
    (uint256 _uuid, address _owner, address _platform) =
      (_projectConfig.uuid, _projectConfig.creator, _projectConfig.platform);
    uuid = _uuid;
    __Ownable_init(_owner);
    __ReentrancyGuard_init();
    PLATFORM = _platform;
    
    // Validate configuration
    if (_implConfig.pricePerToken == 0) revert Tokenizacion_InvalidConfig();
    if (_implConfig.totalTokens == 0) revert Tokenizacion_InvalidConfig();
    if (_implConfig.presaleEnabled) {
      if (_implConfig.presaleStartsAt == 0) revert Tokenizacion_InvalidConfig();
      if (_implConfig.publicSaleStartsAt > 0 && _implConfig.presaleStartsAt >= _implConfig.publicSaleStartsAt) {
        revert Tokenizacion_InvalidConfig();
      }
    }
    
    _config = _implConfig;
    _totalSold = 0;
  }

  /// --- LOGIC FUNCTIONS ---

  /// @inheritdoc ITokenizacion
  function purchaseTokens(uint256 _amount) external payable nonReentrant saleActive {
    if (_amount == 0) revert Tokenizacion_InvalidAmount();
    if (_config.token != address(0)) revert Tokenizacion_InvalidPaymentMethod();

    _validatePresaleAccess();
    _purchaseTokens(_amount, msg.value);
  }

  /// @inheritdoc ITokenizacion
  function purchaseTokensWithERC20(uint256 _amount) external nonReentrant saleActive {
    if (_amount == 0) revert Tokenizacion_InvalidAmount();
    if (_config.token == address(0)) revert Tokenizacion_InvalidPaymentMethod();

    _validatePresaleAccess();

    uint256 _paymentAmount = _amount * _config.pricePerToken;
    IERC20(_config.token).safeTransferFrom(msg.sender, address(this), _paymentAmount);

    _purchaseTokens(_amount, _paymentAmount);
  }

  /// @inheritdoc ITokenizacion
  function addInvestor(address _investor) external onlyOwner {
    if (_isInvestor[_investor]) return; // Already an investor

    _isInvestor[_investor] = true;
    _investors.push(_investor);
    // Note: Platform registration is separate - owner decides when to register
    emit InvestorAdded(_investor);
  }

  /// --- VIEW FUNCTIONS ---

  /// @inheritdoc ITokenizacion
  function config() external view returns (TokenizacionParams memory) {
    return _config;
  }

  /// @inheritdoc ITokenizacion
  /// @notice Returns the list of all investors (whitelisted + buyers)
  /// @dev This array grows with each new investor. For production use, prefer events for off-chain indexing.
  function investors() external view returns (address[] memory) {
    return _investors;
  }

  /// @inheritdoc ITokenizacion
  /// @notice Returns the internal balance of purchased tokens for an investor
  /// @dev This is NOT an ERC20 balance - these are non-transferable project positions
  function balanceOf(address _investor) external view returns (uint256) {
    return _balances[_investor];
  }

  /// @inheritdoc ITokenizacion
  function totalTokensSold() external view returns (uint256) {
    return _totalSold;
  }

  /// @inheritdoc ITokenizacion
  function totalTokensAvailable() external view returns (uint256) {
    return _config.totalTokens - _totalSold;
  }

  /// @inheritdoc ITokenizacion
  function isInvestor(address _investor) external view returns (bool) {
    return _isInvestor[_investor];
  }

  /// @inheritdoc ITokenizacion
  function isPresaleActive() external view returns (bool) {
    return _isPresaleActive();
  }

  /// @inheritdoc ITokenizacion
  function isPublicSaleActive() external view returns (bool) {
    return _isPublicSaleActive();
  }

  /// @inheritdoc ITokenizacion
  function withdrawFunds(address payable _to) external onlyOwner {
    if (_config.token == address(0)) {
      uint256 balance = address(this).balance;
      if (balance == 0) revert Tokenizacion_InsufficientPayment();
      (bool success,) = _to.call{value: balance}('');
      if (!success) revert Tokenizacion_TransferFailed();
    } else {
      uint256 balance = IERC20(_config.token).balanceOf(address(this));
      if (balance == 0) revert Tokenizacion_InsufficientPayment();
      IERC20(_config.token).safeTransfer(_to, balance);
    }
  }

  /// @inheritdoc ITokenizacion
  function cost(uint256 _amount) external view returns (uint256) {
    return _amount * _config.pricePerToken;
  }

  /// @inheritdoc ITokenizacion
  function remainingTokens() external view returns (uint256) {
    return _config.totalTokens - _totalSold;
  }

  /// --- INTERNAL FUNCTIONS ---

  /**
   * @notice Internal function to purchase tokens
   * @param _amount The amount of tokens to purchase
   * @param _paymentAmount The payment amount received
   */
  function _purchaseTokens(uint256 _amount, uint256 _paymentAmount) internal {
    uint256 _requiredPayment = _amount * _config.pricePerToken;
    if (_paymentAmount < _requiredPayment) revert Tokenizacion_InsufficientPayment();

    if (_totalSold + _amount > _config.totalTokens) revert Tokenizacion_InsufficientTokens();

    // Update state BEFORE external calls (CEI pattern)
    _balances[msg.sender] += _amount;
    _totalSold += _amount;

    // Track new buyer (separate from whitelist investor)
    bool isNewBuyer = _balances[msg.sender] == _amount; // First purchase
    if (isNewBuyer && !_isInvestor[msg.sender]) {
      _investors.push(msg.sender);
      // Note: Platform registration handled separately by owner/backend
    }

    // Refund excess payment using call (not transfer)
    if (_paymentAmount > _requiredPayment) {
      uint256 excess = _paymentAmount - _requiredPayment;
      if (_config.token == address(0)) {
        (bool success,) = payable(msg.sender).call{value: excess}('');
        if (!success) revert Tokenizacion_TransferFailed();
      } else {
        IERC20(_config.token).safeTransfer(msg.sender, excess);
      }
    }

    emit TokensPurchased(msg.sender, _amount, _requiredPayment);
  }

  /**
   * @notice Validates presale access if presale is enabled
   */
  function _validatePresaleAccess() internal view {
    if (_isPresaleActive() && !_isInvestor[msg.sender]) {
      revert Tokenizacion_NotInvestor();
    }
  }

  /**
   * @notice Checks if presale is active
   * @dev Presale is active only if:
   *      - presaleEnabled is true
   *      - presaleStartsAt > 0 and current time >= presaleStartsAt
   *      - publicSaleStartsAt is 0 OR current time < publicSaleStartsAt
   * @return _isActive True if presale is active
   */
  function _isPresaleActive() internal view returns (bool _isActive) {
    if (!_config.presaleEnabled) return false;
    if (_config.presaleStartsAt == 0) return false;
    if (block.timestamp < _config.presaleStartsAt) return false;
    // Presale ends when public sale starts (if configured)
    if (_config.publicSaleStartsAt > 0 && block.timestamp >= _config.publicSaleStartsAt) return false;
    return true;
  }

  /**
   * @notice Checks if public sale is active
   * @dev Public sale is active if:
   *      - presale is not enabled OR presale has ended
   *      - publicSaleStartsAt is 0 (always active) OR current time >= publicSaleStartsAt
   * @return _isActive True if public sale is active
   */
  function _isPublicSaleActive() internal view returns (bool _isActive) {
    // If presale is enabled and active, public sale is not active
    if (_isPresaleActive()) return false;
    
    // If publicSaleStartsAt is 0, public sale is always active (after presale if exists)
    if (_config.publicSaleStartsAt == 0) {
      // If presale is enabled, wait for presale to start
      if (_config.presaleEnabled && block.timestamp < _config.presaleStartsAt) return false;
      return true;
    }
    
    // Public sale starts at publicSaleStartsAt
    return block.timestamp >= _config.publicSaleStartsAt;
  }

  /**
   * @notice Checks if any sale is active (presale or public)
   * @dev Sale is active if either presale or public sale is active
   *      Prevents purchases before presale starts if presale is enabled
   * @return _isActive True if any sale is active
   */
  function _isSaleActive() internal view returns (bool _isActive) {
    // If presale is enabled, sale is not active before presale starts
    if (_config.presaleEnabled) {
      if (_config.presaleStartsAt > 0 && block.timestamp < _config.presaleStartsAt) {
        return false;
      }
    }
    
    return _isPresaleActive() || _isPublicSaleActive();
  }
}
