// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPlatform} from "interfaces/IPlatform.sol";
import {ITracking} from "interfaces/ITracking.sol";

/**
 * @title ITokenizacion
 * @author K-Labs
 * @notice Interface for tokenization project contracts
 * @dev Implements internal token sale mechanism for non-transferable project positions
 * @dev Tokens represent non-transferable project ownership positions (NOT ERC20)
 * @dev Supports optional presale phase with whitelist and public sale phase
 */
interface ITokenizacion is ITracking {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tokenization configuration parameters
     * @param paymentToken Payment token address (address(0) for native currency)
     * @param pricePerToken Price per internal token unit
     * @param totalTokens Total number of tokens available for sale
     * @param presaleEnabled Whether presale phase is enabled
     * @param presaleStartsAt Timestamp when presale starts (0 if disabled)
     * @param publicSaleStartsAt Timestamp when public sale starts (0 if immediate)
     */
    struct TokenizacionParams {
        address paymentToken;
        uint256 pricePerToken;
        uint256 totalTokens;
        bool presaleEnabled;
        uint256 presaleStartsAt;
        uint256 publicSaleStartsAt;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the tokenization contract is initialized
     * @param projectId Project ID from platform
     * @param creator Creator address
     * @param totalTokens Total tokens available for sale
     * @param pricePerToken Price per token
     * @param presaleEnabled Whether presale is enabled
     */
    event TokenizacionInitialized(
        uint256 indexed projectId,
        address creator,
        uint256 totalTokens,
        uint256 pricePerToken,
        bool presaleEnabled
    );

    /**
     * @notice Emitted when tokens are purchased
     * @param investor Buyer address
     * @param amount Amount of internal tokens purchased
     * @param paymentAmount Payment amount used
     */
    event TokensPurchased(
        address indexed investor,
        uint256 amount,
        uint256 paymentAmount
    );

    /**
     * @notice Emitted when an investor is whitelisted for presale
     * @param investor Investor address
     */
    event InvestorAdded(address indexed investor);

    /**
     * @notice Emitted when multiple investors are whitelisted in batch
     * @param investors Array of investor addresses
     */
    event InvestorsAddedBatch(address[] investors);

    /**
     * @notice Emitted when funds are withdrawn from the contract
     * @param recipient Address that received the funds
     * @param amount Amount withdrawn
     * @param token Token address (address(0) for native currency)
     */
    event FundsWithdrawn(
        address indexed recipient,
        uint256 amount,
        address indexed token
    );

    /**
     * @notice Emitted when excess payment is refunded
     * @param investor Investor address receiving refund
     * @param amount Refund amount
     */
    event ExcessRefunded(address indexed investor, uint256 amount);

    /**
     * @notice Emitted when sale is completed (all tokens sold)
     * @param totalSold Total tokens sold
     * @param totalCollected Total funds collected
     */
    event SaleCompleted(uint256 totalSold, uint256 totalCollected);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sale is not active
    error SaleNotActive();

    /// @notice Insufficient payment for purchase
    error InsufficientPayment();

    /// @notice Insufficient tokens available for sale
    error InsufficientTokens();

    /// @notice Caller is not a whitelisted investor during presale
    error NotInvestor();

    /// @notice Invalid purchase amount
    error InvalidAmount();

    /// @notice Invalid payment method for current configuration
    error InvalidPaymentMethod();

    /// @notice Transfer of funds failed
    error TransferFailed();

    /// @notice Invalid configuration parameters
    error InvalidConfig();

    /// @notice Contract is paused
    error ContractPaused();

    /// @notice Invalid investor address
    error InvalidInvestor();

    /// @notice Investor already whitelisted
    error AlreadyInvestor();

    /// @notice Maximum number of investors reached
    error MaxInvestorsReached();

    /// @notice Invalid recipient address
    error InvalidRecipient();

    /// @notice Insufficient funds to withdraw
    error InsufficientFunds();

    /// @notice Overflow in calculation
    error Overflow();

    /// @notice Sale has already ended
    error SaleEnded();

    /// @notice Purchase would exceed investor limit
    error PurchaseExceedsLimit();

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the tokenization contract
     * @dev Can only be called once per instance
     * @dev Sets up token sale configuration and initial state
     * @param tokenConfig Tokenization configuration
     * @param governanceConfig Governance configuration (reserved for future use)
     * @param projectConfig Project configuration provided by Platform
     */
    function initialize(
        TokenizacionParams calldata tokenConfig,
        IPlatform.GovernanceConfig calldata governanceConfig,
        IPlatform.ProjectConfig calldata projectConfig
    ) external;

    /*//////////////////////////////////////////////////////////////
                            PURCHASE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Purchase tokens using native currency
     * @dev Must send exact payment amount (pricePerToken * amount)
     * @dev Contract must be active (not paused) and sale must be active
     * @param amount Number of tokens to purchase
     */
    function purchaseTokens(uint256 amount) external payable;

    /**
     * @notice Purchase tokens using ERC20 token
     * @dev Contract must be active (not paused) and sale must be active
     * @dev ERC20 token must match configured paymentToken
     * @param amount Number of tokens to purchase
     */
    function purchaseTokensWithERC20(uint256 amount) external;

    /*//////////////////////////////////////////////////////////////
                            ADMINISTRATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds an address to the presale whitelist
     * @dev Only owner can add investors
     * @param investor Address to whitelist
     */
    function addInvestor(address investor) external;

    /**
     * @notice Adds multiple addresses to presale whitelist in batch
     * @dev Only owner can add investors
     * @param investors Array of addresses to whitelist
     */
    function batchAddInvestors(address[] calldata investors) external;

    /**
     * @notice Withdraws collected funds to specified address
     * @dev Only owner can withdraw funds
     * @param recipient Address to receive the funds
     */
    function withdrawFunds(address payable recipient) external;

    /**
     * @notice Pauses the tokenization, stopping purchases
     * @dev Only owner can pause
     */
    function pause() external;

    /**
     * @notice Unpauses the tokenization, resuming purchases
     * @dev Only owner can unpause
     */
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns tokenization configuration
     * @return config Current tokenization parameters
     */
    function config() external view returns (TokenizacionParams memory config);

    /**
     * @notice Returns list of all investors (whitelisted + buyers)
     * @return investors Array of investor addresses
     */
    function investors() external view returns (address[] memory investors);

    /**
     * @notice Returns internal (non-transferable) token balance for an investor
     * @param investor Investor address
     * @return balance Token balance of the investor
     */
    function balanceOf(
        address investor
    ) external view returns (uint256 balance);

    /**
     * @notice Returns total tokens sold
     * @return sold Total number of tokens sold
     */
    function totalTokensSold() external view returns (uint256 sold);

    /**
     * @notice Returns remaining tokens available for sale
     * @return remaining Number of tokens remaining
     */
    function remainingTokens() external view returns (uint256 remaining);

    /**
     * @notice Checks if an address is whitelisted for presale
     * @param investor Address to check
     * @return isWhitelisted True if whitelisted, false otherwise
     */
    function isInvestor(
        address investor
    ) external view returns (bool isWhitelisted);

    /**
     * @notice Checks if presale is currently active
     * @return active True if presale is active, false otherwise
     */
    function isPresaleActive() external view returns (bool active);

    /**
     * @notice Checks if public sale is currently active
     * @return active True if public sale is active, false otherwise
     */
    function isPublicSaleActive() external view returns (bool active);

    /**
     * @notice Calculates cost for specified number of tokens
     * @param amount Number of tokens
     * @return cost Total cost (pricePerToken * amount)
     */
    function cost(uint256 amount) external view returns (uint256 cost);

    /**
     * @notice Returns total funds collected from all purchases
     * @return collected Total amount collected
     */
    function totalCollected() external view returns (uint256 collected);

    /**
     * @notice Returns total number of investors
     * @return count Number of investors
     */
    function investorCount() external view returns (uint256 count);

    /**
     * @notice Returns complete sale status information
     * @return presaleActive Whether presale is active
     * @return publicSaleActive Whether public sale is active
     * @return saleActive Whether any sale is active
     * @return remaining Number of tokens remaining
     */
    function saleStatus()
        external
        view
        returns (
            bool presaleActive,
            bool publicSaleActive,
            bool saleActive,
            uint256 remaining
        );

    /**
     * @notice Returns total funds withdrawn
     * @return withdrawn Total amount withdrawn
     */
    function totalWithdrawn() external view returns (uint256 withdrawn);

    /**
     * @notice Checks if sale has ended (all tokens sold or time expired)
     * @return ended True if sale has ended, false otherwise
     */
    function hasEnded() external view returns (bool ended);

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
        returns (uint256 balance, bool isWhitelisted, uint256 totalSpent);

    /**
     * @notice Returns maximum number of investors allowed
     * @return maxInvestors Maximum investors capacity
     */
    function maxInvestors() external view returns (uint256 maxInvestors);

    /**
     * @notice Returns maximum purchase limit per investor
     * @return maxIndividualPurchase Maximum tokens per investor
     */
    function maxIndividualPurchase()
        external
        view
        returns (uint256 maxIndividualPurchase);

    /**
     * @notice Returns sale end timestamp
     * @return endTime Timestamp when sale ends (0 if indefinite or based on token supply)
     */
    function saleEndTime() external view returns (uint256 endTime);

    /**
     * @notice Returns all configuration constants
     * @return minPurchase Minimum purchase amount
     * @return maxPurchase Maximum single transaction purchase
     * @return maxInvestorsCap Maximum investors capacity
     * @return maxSaleDuration Maximum sale duration in seconds
     * @return maxPerInvestor Maximum tokens per investor
     */
    function getConstants()
        external
        view
        returns (
            uint256 minPurchase,
            uint256 maxPurchase,
            uint256 maxInvestorsCap,
            uint256 maxSaleDuration,
            uint256 maxPerInvestor
        );
}
