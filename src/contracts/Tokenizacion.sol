// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Tracking} from "contracts/Tracking.sol";
import {ITokenizacion} from "interfaces/ITokenizacion.sol";
import {IPlatform} from "interfaces/IPlatform.sol";

/**
 * @title Tokenizacion
 * @dev Internal token sale mechanism for non-transferable project positions
 * @notice Implements token sale with optional presale phase and whitelist
 * @author K-Labs
 * @dev Tokens represent non-transferable project ownership positions (NOT ERC20)
 * @dev Uses upgradeable pattern for potential future improvements
 */
contract Tokenizacion is
    Initializable,
    Tracking,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ITokenizacion
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Minimum purchase amount (1 token)
    uint256 private constant MIN_PURCHASE_AMOUNT = 1;

    /// @dev Maximum purchase amount in a single transaction
    uint256 private constant MAX_PURCHASE_AMOUNT = 1_000_000;

    /// @dev Maximum number of investors (safety limit)
    uint256 private constant MAX_INVESTORS = 10_000;

    /// @dev Maximum sale duration (2 years)
    uint256 private constant MAX_SALE_DURATION = 730 days;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Tokenization configuration
    TokenizacionParams private _config;

    /// @notice Investor token balances (non-transferable positions)
    mapping(address => uint256) private _balances;

    /// @notice Whitelisted investors for presale
    mapping(address => bool) private _isWhitelisted;

    /// @notice List of all investors
    address[] private _investors;

    /// @notice Total tokens sold
    uint256 private _tokensSold;

    /// @notice Total funds collected
    uint256 private _totalCollected;

    /// @notice Total funds withdrawn
    uint256 private _totalWithdrawn;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Restricts access to whitelisted investors only
     */
    modifier onlyWhitelisted() {
        if (!_isWhitelisted[msg.sender]) revert Tokenizacion_NotInvestor();
        _;
    }

    /**
     * @dev Ensures sale is active
     */
    modifier whenSaleActive() {
        if (!_isSaleActive()) revert Tokenizacion_SaleNotActive();
        _;
    }

    /**
     * @dev Restricts access when contract is active (not paused)
     */
    modifier whenActive() {
        if (paused()) revert Tokenizacion_ContractPaused();
        _;
    }

    /**
     * @dev Validates purchase amount
     */
    modifier validAmount(uint256 amount) {
        if (amount < MIN_PURCHASE_AMOUNT) revert Tokenizacion_InvalidAmount();
        if (amount > MAX_PURCHASE_AMOUNT) revert Tokenizacion_InvalidAmount();
        _;
    }

    /**
     * @dev Validates investor address
     */
    modifier validInvestor(address investor) {
        if (investor == address(0)) revert Tokenizacion_InvalidInvestor();
        if (investor == address(this)) revert Tokenizacion_InvalidInvestor();
        _;
    }

    /**
     * @dev Validates recipient address
     */
    modifier validRecipient(address recipient) {
        if (recipient == address(0)) revert Tokenizacion_InvalidRecipient();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITokenizacion
     * @notice Initializes the tokenization contract
     * @dev Sets up configuration, ownership, and initial state
     */
    function initialize(
        TokenizacionParams calldata tokenConfig,
        IPlatform.GovernanceConfig calldata governanceConfig,
        IPlatform.ProjectConfig calldata projectConfig
    ) external override initializer notInitialized {
        // Validate configuration
        _validateConfig(tokenConfig);

        // Initialize Tracking with project information
        __Tracking_init(
            projectConfig.platform,
            projectConfig.projectId,
            projectConfig.creator
        );

        // Initialize other parent contracts
        __Ownable_init(projectConfig.creator);
        __ReentrancyGuard_init();
        __Pausable_init();

        // Store configuration
        _config = tokenConfig;

        emit TokenizacionInitialized(
            projectConfig.projectId,
            projectConfig.creator,
            tokenConfig.totalTokens,
            tokenConfig.pricePerToken,
            tokenConfig.presaleEnabled
        );
    }

    /*//////////////////////////////////////////////////////////////
                            PURCHASE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITokenizacion
     * @notice Purchase tokens with native currency
     */
    function purchaseTokens(
        uint256 amount
    )
        external
        payable
        override
        nonReentrant
        whenActive
        whenSaleActive
        validAmount(amount)
    {
        if (_config.paymentToken != address(0)) {
            revert Tokenizacion_InvalidPaymentMethod();
        }

        _validatePresaleAccess();
        _executePurchase(amount, msg.value);
    }

    /**
     * @inheritdoc ITokenizacion
     * @notice Purchase tokens with ERC20 token
     */
    function purchaseTokensWithERC20(
        uint256 amount
    )
        external
        override
        nonReentrant
        whenActive
        whenSaleActive
        validAmount(amount)
    {
        if (_config.paymentToken == address(0)) {
            revert Tokenizacion_InvalidPaymentMethod();
        }

        _validatePresaleAccess();

        uint256 paymentRequired = amount * _config.pricePerToken;

        IERC20(_config.paymentToken).safeTransferFrom(
            msg.sender,
            address(this),
            paymentRequired
        );

        _executePurchase(amount, paymentRequired);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITokenizacion
     * @notice Add investor to whitelist
     */
    function addInvestor(
        address investor
    ) external override onlyOwner whenActive validInvestor(investor) {
        if (_isWhitelisted[investor]) revert Tokenizacion_AlreadyInvestor();
        if (_investors.length >= MAX_INVESTORS) {
            revert Tokenizacion_MaxInvestorsReached();
        }

        _isWhitelisted[investor] = true;
        _investors.push(investor);

        emit InvestorAdded(investor);
    }

    /**
     * @inheritdoc ITokenizacion
     * @notice Withdraw collected funds to specified address
     */
    function withdrawFunds(
        address payable recipient
    ) external override onlyOwner nonReentrant validRecipient(recipient) {
        uint256 balance;
        address tokenAddress = _config.paymentToken;

        if (tokenAddress == address(0)) {
            // Native currency withdrawal
            balance = address(this).balance;
            if (balance == 0) revert Tokenizacion_InsufficientFunds();

            (bool success, ) = recipient.call{value: balance}("");
            if (!success) revert Tokenizacion_TransferFailed();
        } else {
            // ERC20 token withdrawal
            balance = IERC20(tokenAddress).balanceOf(address(this));
            if (balance == 0) revert Tokenizacion_InsufficientFunds();

            IERC20(tokenAddress).safeTransfer(recipient, balance);
        }

        // Update total withdrawn
        _totalWithdrawn += balance;
        require(_totalWithdrawn >= balance, "Tokenizacion: overflow");

        emit FundsWithdrawn(recipient, balance, tokenAddress);
    }

    /*//////////////////////////////////////////////////////////////
                            EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITokenizacion
     * @notice Pauses the tokenization, stopping purchases
     */
    function pause() external override onlyOwner {
        _pause();
        emit Paused(msg.sender);
    }

    /**
     * @inheritdoc ITokenizacion
     * @notice Unpauses the tokenization, resuming purchases
     */
    function unpause() external override onlyOwner {
        _unpause();
        emit Unpaused(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITokenizacion
     * @notice Returns tokenization configuration
     */
    function config()
        external
        view
        override
        returns (TokenizacionParams memory)
    {
        return _config;
    }

    /**
     * @inheritdoc ITokenizacion
     * @notice Returns list of all investors
     */
    function investors() external view override returns (address[] memory) {
        return _investors;
    }

    /**
     * @inheritdoc ITokenizacion
     * @notice Returns token balance for an investor
     */
    function balanceOf(
        address investor
    ) external view override returns (uint256) {
        return _balances[investor];
    }

    /**
     * @inheritdoc ITokenizacion
     * @notice Returns total tokens sold
     */
    function totalTokensSold() external view override returns (uint256) {
        return _tokensSold;
    }

    /**
     * @inheritdoc ITokenizacion
     * @notice Returns remaining tokens for sale
     */
    function remainingTokens() external view override returns (uint256) {
        return _config.totalTokens - _tokensSold;
    }

    /**
     * @inheritdoc ITokenizacion
     * @notice Checks if address is whitelisted investor
     */
    function isInvestor(
        address investor
    ) external view override returns (bool) {
        return _isWhitelisted[investor];
    }

    /**
     * @inheritdoc ITokenizacion
     * @notice Checks if presale is active
     */
    function isPresaleActive() external view override returns (bool) {
        return _isPresaleActive();
    }

    /**
     * @inheritdoc ITokenizacion
     * @notice Checks if public sale is active
     */
    function isPublicSaleActive() external view override returns (bool) {
        return _isPublicSaleActive();
    }

    /**
     * @inheritdoc ITokenizacion
     * @notice Calculates cost for specified token amount
     */
    function cost(uint256 amount) external view override returns (uint256) {
        if (amount == 0) return 0;
        return amount * _config.pricePerToken;
    }

    /**
     * @inheritdoc ITokenizacion
     * @notice Returns total funds collected
     */
    function totalCollected() external view override returns (uint256) {
        return _totalCollected;
    }

    /**
     * @inheritdoc ITokenizacion
     * @notice Returns total number of investors
     */
    function investorCount() external view override returns (uint256) {
        return _investors.length;
    }

    /**
     * @inheritdoc ITokenizacion
     * @notice Returns sale status information
     */
    function saleStatus()
        external
        view
        override
        returns (
            bool presaleActive,
            bool publicSaleActive,
            bool saleActive,
            uint256 remaining
        )
    {
        return (
            _isPresaleActive(),
            _isPublicSaleActive(),
            _isSaleActive(),
            _config.totalTokens - _tokensSold
        );
    }

    /**
     * @notice Returns total funds withdrawn
     * @return Total amount withdrawn
     */
    function totalWithdrawn() external view returns (uint256) {
        return _totalWithdrawn;
    }

    /**
     * @notice Returns available balance in contract
     * @return Current contract balance (native or ERC20)
     */
    function availableBalance() external view returns (uint256) {
        if (_config.paymentToken == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(_config.paymentToken).balanceOf(address(this));
        }
    }

    /**
     * @notice Checks if sale has ended (all tokens sold or time expired)
     * @return True if sale has ended, false otherwise
     */
    function hasEnded() external view returns (bool) {
        if (_tokensSold >= _config.totalTokens) return true;

        // Check if sale duration exceeded (if public sale has start time)
        if (_config.publicSaleStartsAt > 0) {
            uint256 saleEnd = _config.publicSaleStartsAt + MAX_SALE_DURATION;
            return block.timestamp > saleEnd;
        }

        return false;
    }

    /**
     * @notice Returns investor information
     * @param investor Investor address
     * @return balance Token balance
     * @return isWhitelisted Whether investor is whitelisted
     * @return totalSpent Total amount spent by investor
     */
    function getInvestorInfo(
        address investor
    )
        external
        view
        returns (uint256 balance, bool isWhitelisted, uint256 totalSpent)
    {
        balance = _balances[investor];
        isWhitelisted = _isWhitelisted[investor];
        totalSpent = balance * _config.pricePerToken;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Executes token purchase
     * @param amount Token amount to purchase
     * @param paid Amount paid by investor
     */
    function _executePurchase(uint256 amount, uint256 paid) internal {
        uint256 required = amount * _config.pricePerToken;

        // Validate payment
        if (paid < required) revert Tokenizacion_InsufficientPayment();

        // Validate token availability
        if (_tokensSold + amount > _config.totalTokens) {
            revert Tokenizacion_InsufficientTokens();
        }

        // Update investor balance if first purchase
        bool isFirstPurchase = _balances[msg.sender] == 0;

        // Update balances with overflow checks
        uint256 newBalance = _balances[msg.sender] + amount;
        require(
            newBalance >= _balances[msg.sender],
            "Tokenizacion: balance overflow"
        );

        uint256 newTokensSold = _tokensSold + amount;
        require(
            newTokensSold >= _tokensSold,
            "Tokenizacion: tokens sold overflow"
        );

        uint256 newTotalCollected = _totalCollected + required;
        require(
            newTotalCollected >= _totalCollected,
            "Tokenizacion: total overflow"
        );

        _balances[msg.sender] = newBalance;
        _tokensSold = newTokensSold;
        _totalCollected = newTotalCollected;

        // Add to investors list if first purchase and not already in list
        if (isFirstPurchase && !_isWhitelisted[msg.sender]) {
            require(
                _investors.length < MAX_INVESTORS,
                "Tokenizacion: max investors"
            );
            _investors.push(msg.sender);
        }

        // Handle refund if overpaid
        if (paid > required) {
            uint256 refund = paid - required;
            _processRefund(refund);
        }

        emit TokensPurchased(msg.sender, amount, required);
    }

    /**
     * @dev Processes refund for overpayment
     * @param refundAmount Amount to refund
     */
    function _processRefund(uint256 refundAmount) internal {
        if (_config.paymentToken == address(0)) {
            // Native currency refund
            (bool success, ) = payable(msg.sender).call{value: refundAmount}(
                ""
            );
            if (!success) revert Tokenizacion_TransferFailed();
        } else {
            // ERC20 token refund
            IERC20(_config.paymentToken).safeTransfer(msg.sender, refundAmount);
        }
    }

    /**
     * @dev Validates presale access
     */
    function _validatePresaleAccess() internal view {
        if (_isPresaleActive() && !_isWhitelisted[msg.sender]) {
            revert Tokenizacion_NotInvestor();
        }
    }

    /**
     * @dev Checks if presale is active
     */
    function _isPresaleActive() internal view returns (bool) {
        if (!_config.presaleEnabled) return false;
        if (block.timestamp < _config.presaleStartsAt) return false;

        if (
            _config.publicSaleStartsAt > 0 &&
            block.timestamp >= _config.publicSaleStartsAt
        ) return false;

        return true;
    }

    /**
     * @dev Checks if public sale is active
     */
    function _isPublicSaleActive() internal view returns (bool) {
        if (_isPresaleActive()) return false;

        if (_config.publicSaleStartsAt == 0) {
            if (
                _config.presaleEnabled &&
                block.timestamp < _config.presaleStartsAt
            ) return false;
            return true;
        }

        return block.timestamp >= _config.publicSaleStartsAt;
    }

    /**
     * @dev Checks if any sale is active
     */
    function _isSaleActive() internal view returns (bool) {
        if (_config.presaleEnabled) {
            if (
                _config.presaleStartsAt > 0 &&
                block.timestamp < _config.presaleStartsAt
            ) return false;
        }

        // Check if sale has ended (all tokens sold)
        if (_tokensSold >= _config.totalTokens) return false;

        return _isPresaleActive() || _isPublicSaleActive();
    }

    /**
     * @dev Validates tokenization configuration
     * @param config_ Configuration to validate
     */
    function _validateConfig(TokenizacionParams calldata config_) private pure {
        if (config_.totalTokens == 0) revert Tokenizacion_InvalidConfig();
        if (config_.pricePerToken == 0) revert Tokenizacion_InvalidConfig();

        if (config_.presaleEnabled) {
            if (config_.presaleStartsAt == 0) {
                revert Tokenizacion_InvalidConfig();
            }
            if (
                config_.publicSaleStartsAt > 0 &&
                config_.presaleStartsAt >= config_.publicSaleStartsAt
            ) {
                revert Tokenizacion_InvalidConfig();
            }
        }

        // Validate reasonable sale duration
        if (config_.publicSaleStartsAt > 0) {
            if (
                config_.publicSaleStartsAt > block.timestamp + MAX_SALE_DURATION
            ) {
                revert Tokenizacion_InvalidConfig();
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                                RECEIVE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows the contract to receive ETH
     * @dev Required for native token purchases
     */
    receive() external payable {}
}
