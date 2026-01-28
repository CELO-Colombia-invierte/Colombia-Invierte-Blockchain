// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Tracking} from "contracts/Tracking.sol";
import {ITokenizacion} from "interfaces/ITokenizacion.sol";
import {IPlatform} from "interfaces/IPlatform.sol";

/**
 * @title Tokenizacion
 * @author K-Labs
 * @notice Internal token sale mechanism for non-transferable project positions
 * @dev Implements token sale with optional presale phase and whitelist
 * @dev Tokens represent non-transferable project ownership positions (NOT ERC20)
 * @custom:features Presale whitelist, native/ERC20 payments, batch operations
 */
contract Tokenizacion is
    Initializable,
    Tracking,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ITokenizacion
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Minimum purchase amount (1 token)
    uint256 private constant MIN_PURCHASE_AMOUNT = 1;

    /// @notice Maximum purchase amount in a single transaction
    uint256 private constant MAX_PURCHASE_AMOUNT = 1_000_000;

    /// @notice Maximum number of investors (safety limit)
    uint256 private constant MAX_INVESTORS = 10_000;

    /// @notice Maximum sale duration (2 years)
    uint256 private constant MAX_SALE_DURATION = 730 days;

    /// @notice Maximum individual investor purchase limit (in tokens)
    uint256 private constant MAX_INDIVIDUAL_PURCHASE = 100_000;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Tokenization configuration parameters
    TokenizacionParams private _config;

    /// @inheritdoc ITokenizacion
    mapping(address => uint256) public override balanceOf;

    /// @inheritdoc ITokenizacion
    mapping(address => bool) public override isInvestor;

    /// @notice List of all investors
    address[] private _investors;

    /// @inheritdoc ITokenizacion
    uint256 public override totalTokensSold;

    /// @inheritdoc ITokenizacion
    uint256 public override totalCollected;

    /// @inheritdoc ITokenizacion
    uint256 public override totalWithdrawn;

    /// @notice Total refunds issued
    uint256 private _totalRefunded;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Restricts access to whitelisted investors only during presale
     */
    modifier onlyWhitelistedDuringPresale() {
        if (_isPresaleActive() && !isInvestor[msg.sender]) revert NotInvestor();
        _;
    }

    /**
     * @dev Ensures sale is active before purchase
     */
    modifier whenSaleActive() {
        if (!_isSaleActive()) revert SaleNotActive();
        if (_hasSaleEnded()) revert SaleEnded();
        _;
    }

    /**
     * @dev Restricts access when contract is active (not paused)
     */
    modifier whenActive() {
        if (paused()) revert ContractPaused();
        _;
    }

    /**
     * @dev Validates purchase amount within transaction limits
     * @dev Does NOT check individual investor limits (checked in _processPurchase)
     */
    modifier validAmount(uint256 amount) {
        if (amount < MIN_PURCHASE_AMOUNT) revert InvalidAmount();
        if (amount > MAX_PURCHASE_AMOUNT) revert InvalidAmount();
        _;
    }

    /**
     * @dev Validates investor address
     */
    modifier validAddress(address addr) {
        if (addr == address(0) || addr == address(this))
            revert InvalidInvestor();
        _;
    }

    /**
     * @dev Validates recipient address for withdrawals
     */
    modifier validRecipient(address recipient) {
        if (recipient == address(0)) revert InvalidRecipient();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITokenizacion
     * @dev Validates configuration parameters and sets up initial state
     * @dev The governanceConfig parameter is reserved for future use
     */
    function initialize(
        TokenizacionParams calldata tokenConfig,
        IPlatform.GovernanceConfig calldata,
        IPlatform.ProjectConfig calldata projectConfig
    ) external override initializer {
        // Validate configuration
        _validateConfig(tokenConfig);

        // Initialize parent contracts
        __Tracking_init(
            projectConfig.platform,
            projectConfig.projectId,
            projectConfig.creator
        );
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
     * @dev Validates payment method and processes native currency purchase
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
        onlyWhitelistedDuringPresale
    {
        if (_config.paymentToken != address(0)) revert InvalidPaymentMethod();

        _processPurchase(amount, msg.value);
    }

    /**
     * @inheritdoc ITokenizacion
     * @dev Validates payment method and processes ERC20 purchase
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
        onlyWhitelistedDuringPresale
    {
        if (_config.paymentToken == address(0)) revert InvalidPaymentMethod();

        uint256 paymentRequired = amount * _config.pricePerToken;

        IERC20(_config.paymentToken).safeTransferFrom(
            msg.sender,
            address(this),
            paymentRequired
        );

        _processPurchase(amount, paymentRequired);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMINISTRATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITokenizacion
     * @dev Adds single investor to whitelist
     */
    function addInvestor(
        address investor
    ) external override whenActive validAddress(investor) {
        _requireOwner();
        if (isInvestor[investor]) revert AlreadyInvestor();
        if (_investors.length >= MAX_INVESTORS) revert MaxInvestorsReached();

        isInvestor[investor] = true;
        _investors.push(investor);

        emit InvestorAdded(investor);
    }

    /**
     * @inheritdoc ITokenizacion
     * @dev Adds multiple newInvestors to whitelist in batch
     */
    function batchAddInvestors(
        address[] calldata newInvestors
    ) external override whenActive {
        _requireOwner();
        uint256 count = newInvestors.length;
        address[] memory addedInvestors = new address[](count);
        uint256 addedCount = 0;

        for (uint256 i = 0; i < count; ) {
            address investor = newInvestors[i];
            if (
                investor != address(0) &&
                investor != address(this) &&
                !isInvestor[investor]
            ) {
                if (_investors.length < MAX_INVESTORS) {
                    isInvestor[investor] = true;
                    _investors.push(investor);
                    addedInvestors[addedCount] = investor;
                    addedCount++;
                }
            }
            unchecked {
                ++i;
            }
        }

        if (addedCount > 0) {
            address[] memory finalAdded = new address[](addedCount);
            for (uint256 j = 0; j < addedCount; j++) {
                finalAdded[j] = addedInvestors[j];
            }
            emit InvestorsAddedBatch(finalAdded);
        }
    }

    /**
     * @inheritdoc ITokenizacion
     * @dev Withdraws collected funds to specified address
     */
    function withdrawFunds(
        address payable recipient
    ) external override nonReentrant validRecipient(recipient) {
        _requireOwner();
        uint256 balance;
        address tokenAddress = _config.paymentToken;

        if (tokenAddress == address(0)) {
            // Native currency withdrawal
            balance = address(this).balance;
        } else {
            // ERC20 token withdrawal
            balance = IERC20(tokenAddress).balanceOf(address(this));
        }

        if (balance == 0) revert InsufficientFunds();

        // Update total withdrawn
        totalWithdrawn += balance;

        // Transfer funds
        if (tokenAddress == address(0)) {
            (bool success, ) = recipient.call{value: balance}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(tokenAddress).safeTransfer(recipient, balance);
        }

        emit FundsWithdrawn(recipient, balance, tokenAddress);
    }

    /**
     * @inheritdoc ITokenizacion
     */
    function pause() external override {
        _requireOwner();
        _pause();
    }

    /**
     * @inheritdoc ITokenizacion
     */
    function unpause() external override {
        _requireOwner();
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITokenizacion
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
     */
    function investors() external view override returns (address[] memory) {
        return _investors;
    }

    /**
     * @inheritdoc ITokenizacion
     */
    function remainingTokens() external view override returns (uint256) {
        return _config.totalTokens - totalTokensSold;
    }

    /**
     * @inheritdoc ITokenizacion
     */
    function isPresaleActive() external view override returns (bool) {
        return _isPresaleActive();
    }

    /**
     * @inheritdoc ITokenizacion
     */
    function isPublicSaleActive() external view override returns (bool) {
        return _isPublicSaleActive();
    }

    /**
     * @inheritdoc ITokenizacion
     */
    function cost(uint256 amount) external view override returns (uint256) {
        return amount * _config.pricePerToken;
    }

    /**
     * @inheritdoc ITokenizacion
     */
    function investorCount() external view override returns (uint256) {
        return _investors.length;
    }

    /**
     * @inheritdoc ITokenizacion
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
            _config.totalTokens - totalTokensSold
        );
    }

    /**
     * @inheritdoc ITokenizacion
     */
    function hasEnded() external view override returns (bool) {
        return _hasSaleEnded();
    }

    /**
     * @inheritdoc ITokenizacion
     */
    function getInvestorInfo(
        address investor
    )
        external
        view
        override
        returns (uint256 balance, bool isWhitelisted, uint256 totalSpent)
    {
        balance = balanceOf[investor];
        isWhitelisted = isInvestor[investor];
        totalSpent = balance * _config.pricePerToken;
    }

    /**
     * @inheritdoc ITokenizacion
     */
    function maxInvestors() external pure override returns (uint256) {
        return MAX_INVESTORS;
    }

    /**
     * @inheritdoc ITokenizacion
     */
    function maxIndividualPurchase() external pure override returns (uint256) {
        return MAX_INDIVIDUAL_PURCHASE;
    }

    /**
     * @inheritdoc ITokenizacion
     */
    function saleEndTime() external view override returns (uint256 endTime) {
        if (_config.publicSaleStartsAt > 0) {
            return _config.publicSaleStartsAt + MAX_SALE_DURATION;
        }
        return 0;
    }

    /**
     * @inheritdoc ITokenizacion
     */
    function getConstants()
        external
        pure
        override
        returns (
            uint256 minPurchase,
            uint256 maxPurchase,
            uint256 maxInvestorsCap,
            uint256 maxSaleDuration,
            uint256 maxPerInvestor
        )
    {
        return (
            MIN_PURCHASE_AMOUNT,
            MAX_PURCHASE_AMOUNT,
            MAX_INVESTORS,
            MAX_SALE_DURATION,
            MAX_INDIVIDUAL_PURCHASE
        );
    }

    /**
     * @notice Returns total refunds issued
     * @return refunded Total amount refunded
     */
    function totalRefunded() external view returns (uint256 refunded) {
        return _totalRefunded;
    }

    /**
     * @notice Returns available balance in contract
     * @return balance Current contract balance (native or ERC20)
     */
    function availableBalance() external view returns (uint256 balance) {
        if (_config.paymentToken == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(_config.paymentToken).balanceOf(address(this));
        }
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Processes token purchase with payment validation
     * @dev Includes individual investor limit check (MAX_INDIVIDUAL_PURCHASE)
     * @param amount Token amount to purchase
     * @param paid Amount paid by investor
     */
    function _processPurchase(uint256 amount, uint256 paid) internal {
        uint256 required = amount * _config.pricePerToken;

        // Validate payment
        if (paid < required) revert InsufficientPayment();

        // Validate token availability
        if (totalTokensSold + amount > _config.totalTokens) {
            revert InsufficientTokens();
        }

        // Validate individual purchase limit (this is the correct check)
        uint256 newBalance = balanceOf[msg.sender] + amount;
        if (newBalance > MAX_INDIVIDUAL_PURCHASE) revert PurchaseExceedsLimit();

        // Update investor balance if first purchase
        bool isFirstPurchase = balanceOf[msg.sender] == 0;

        // Update state with overflow checks
        balanceOf[msg.sender] = newBalance;
        totalTokensSold += amount;
        totalCollected += required;

        // Add to investors list if first purchase and not already whitelisted
        if (isFirstPurchase && !isInvestor[msg.sender]) {
            if (_investors.length >= MAX_INVESTORS)
                revert MaxInvestorsReached();
            _investors.push(msg.sender);
        }

        // Handle refund if overpaid
        if (paid > required) {
            uint256 refund = paid - required;
            _processRefund(refund);
        }

        // Check if sale is now complete
        if (totalTokensSold == _config.totalTokens) {
            emit SaleCompleted(totalTokensSold, totalCollected);
        }

        emit TokensPurchased(msg.sender, amount, required);
    }

    /**
     * @dev Processes refund for overpayment
     * @param refundAmount Amount to refund
     */
    function _processRefund(uint256 refundAmount) internal {
        _totalRefunded += refundAmount;

        if (_config.paymentToken == address(0)) {
            // Native currency refund
            (bool success, ) = payable(msg.sender).call{value: refundAmount}(
                ""
            );
            if (!success) revert TransferFailed();
        } else {
            // ERC20 token refund
            IERC20(_config.paymentToken).safeTransfer(msg.sender, refundAmount);
        }

        emit ExcessRefunded(msg.sender, refundAmount);
    }

    /**
     * @dev Checks if presale is currently active
     * @return True if presale is active
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
     * @dev Checks if public sale is currently active
     * @return True if public sale is active
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
     * @dev Checks if any sale is currently active
     * @return True if sale is active
     */
    function _isSaleActive() internal view returns (bool) {
        if (_config.presaleEnabled) {
            if (
                _config.presaleStartsAt > 0 &&
                block.timestamp < _config.presaleStartsAt
            ) return false;
        }

        // Check if all tokens sold
        if (totalTokensSold >= _config.totalTokens) return false;

        return _isPresaleActive() || _isPublicSaleActive();
    }

    /**
     * @dev Checks if sale has ended (time expired or all tokens sold)
     * @return True if sale has ended
     */
    function _hasSaleEnded() internal view returns (bool) {
        if (totalTokensSold >= _config.totalTokens) return true;

        // Check if sale duration exceeded
        if (_config.publicSaleStartsAt > 0) {
            uint256 saleEnd = _config.publicSaleStartsAt + MAX_SALE_DURATION;
            return block.timestamp > saleEnd;
        }

        return false;
    }

    /**
     * @dev Validates tokenization configuration parameters
     * @dev Maximum sale duration is 2 years (730 days) from public sale start
     * @dev If publicSaleStartsAt = 0 and presaleEnabled = true:
     *      - Presale runs from presaleStartsAt
     *      - Public sale starts immediately after presale period
     * @dev Prevents creating sales that start too far in the future (>2 years)
     * @param config_ Configuration to validate
     */
    function _validateConfig(TokenizacionParams calldata config_) private view {
        if (config_.totalTokens == 0) revert InvalidConfig();
        if (config_.pricePerToken == 0) revert InvalidConfig();

        if (config_.presaleEnabled) {
            if (config_.presaleStartsAt == 0) revert InvalidConfig();
            if (
                config_.publicSaleStartsAt > 0 &&
                config_.presaleStartsAt >= config_.publicSaleStartsAt
            ) revert InvalidConfig();
        }

        // Validate reasonable sale duration (MAX 2 years)
        if (config_.publicSaleStartsAt > 0) {
            if (
                config_.publicSaleStartsAt > block.timestamp + MAX_SALE_DURATION
            ) revert InvalidConfig();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows contract to receive ETH
     * @dev Required for native currency purchases
     */
    receive() external payable {}
}
