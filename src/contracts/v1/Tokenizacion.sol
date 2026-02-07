// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ITokenizacion} from "../../interfaces/v1/ITokenizacion.sol";
import {ProjectToken} from "./ProjectToken.sol";

/**
 * @title Tokenizacion
 * @notice Simple token sale with fixed price
 * @dev MVP V1: Basic token sale without whitelists, presale, or complex features
 */
contract Tokenizacion is Ownable, ReentrancyGuard, ITokenizacion {
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                                STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether contract is initialized
    bool private _initialized;

    /// @notice Sale configuration parameters
    Config private _config;

    /// @notice Project information
    ProjectInfo private _projectInfo;

    /// @notice Project token contract instance
    ProjectToken public projectToken;

    /// @notice Total tokens sold
    uint256 public tokensSold;

    /// @notice Total funds collected (in payment token decimals)
    uint256 public fundsCollected;

    /// @notice Whether sale has been finalized
    bool public saleFinalized;

    /*///////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Disable direct deployment
     * @dev Contract must be deployed via Platform factory
     */
    constructor() Ownable(msg.sender) {
        // owner will be replaced in initialize()
    }

    /*///////////////////////////////////////////////////////////////
                                INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the token sale with configuration
     * @param config_ Token sale configuration parameters
     * @param info_ Project information structure
     * @dev Can only be called once per contract instance
     * @dev Creates ProjectToken ERC20 token with dynamic name/symbol
     * @dev Transfers ownership to project creator
     */
    function initialize(
        Config calldata config_,
        ProjectInfo calldata info_
    ) external {
        // Ensure single initialization
        if (_initialized) revert AlreadyInitialized();

        // Validate configuration parameters
        if (config_.totalTokens == 0) revert InvalidPayment();
        if (config_.pricePerToken == 0) revert InvalidPayment();
        if (config_.saleDuration == 0) revert InvalidPayment();
        if (config_.paymentToken != address(0)) {
            IERC20(config_.paymentToken).totalSupply();
        }

        // Store configuration
        _config = config_;
        _projectInfo = info_;
        _initialized = true;

        // Create project token with dynamic name and symbol
        string memory name = string(
            abi.encodePacked("Project ", Strings.toString(info_.projectId))
        );
        string memory symbol = string(
            abi.encodePacked("PRJ", Strings.toString(info_.projectId))
        );

        projectToken = new ProjectToken(name, symbol, address(this));

        // Transfer ownership to project creator
        _transferOwnership(info_.creator);
    }

    /*///////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Purchase tokens from the sale
     * @param amount Number of tokens to purchase (in token units, not wei)
     * @dev Example: amount = 100 means 100 project tokens, not 100 wei
     * @dev Cost = amount * pricePerToken (in payment token decimals)
     * @dev Supports both ETH (address(0)) and ERC20 payments
     * @dev Auto-finalizes sale if all tokens are sold
     * @dev Emits TokensPurchased event on successful purchase
     */
    function buyTokens(uint256 amount) external payable nonReentrant {
        // Validate sale state
        if (saleFinalized) revert SaleEnded();
        if (!_isSaleActive()) revert SaleNotActive();
        if (tokensSold + amount > _config.totalTokens)
            revert InsufficientTokens();

        // Calculate purchase cost (uses built-in overflow protection in Solidity 0.8)
        uint256 cost = amount * _config.pricePerToken;
        // Process payment based on token type
        if (_config.paymentToken == address(0)) {
            // Native ETH payment validation
            if (msg.value != cost) revert InvalidPayment();
        } else {
            // ERC20 payment - transfer from buyer to contract
            IERC20(_config.paymentToken).safeTransferFrom(
                msg.sender,
                address(this),
                cost
            );
        }

        // Update sale state
        tokensSold += amount;
        fundsCollected += cost;

        // Mint purchased tokens to buyer
        projectToken.mint(msg.sender, amount);

        emit TokensPurchased(msg.sender, amount, cost);

        // Auto-finalize if all tokens are sold
        if (tokensSold == _config.totalTokens) {
            _finalizeSale();
        }
    }

    /**
     * @notice Finalize the token sale manually
     * @dev Can only be called by contract owner (project creator)
     * @dev Disables further token purchases and finalizes token minting
     */
    function finalizeSale() external onlyOwner {
        if (block.timestamp < _config.saleStart + _config.saleDuration) {
            revert SaleNotActive();
        }
        _finalizeSale();
    }

    /**
     * @notice Withdraw collected funds to owner
     * @dev Can only be called by contract owner after sale is finalized
     * @dev Supports both ETH and ERC20 token withdrawals
     * @dev Emits FundsWithdrawn event on successful withdrawal
     */
    function withdrawFunds() external onlyOwner nonReentrant {
        if (!saleFinalized) revert SaleNotActive();

        uint256 balance;

        if (_config.paymentToken == address(0)) {
            // Withdraw native ETH balance
            balance = address(this).balance;
            if (balance == 0) revert InvalidPayment();

            (bool success, ) = owner().call{value: balance}("");
            if (!success) revert InvalidPayment();
        } else {
            // Withdraw ERC20 token balance
            IERC20 token = IERC20(_config.paymentToken);
            balance = token.balanceOf(address(this));
            if (balance == 0) revert InvalidPayment();

            token.safeTransfer(owner(), balance);
        }

        emit FundsWithdrawn(owner(), balance);
    }

    /*///////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if sale is currently active
     * @return bool True if sale is active, false otherwise
     * @dev Sale is active if: not finalized, within sale period, and tokens remain
     */
    function isSaleActive() external view returns (bool) {
        return _isSaleActive();
    }

    /**
     * @notice Get number of remaining tokens available for purchase
     * @return uint256 Count of tokens still available in the sale
     */
    function remainingTokens() external view returns (uint256) {
        return _config.totalTokens - tokensSold;
    }

    /**
     * @notice Get the sale configuration parameters
     * @return Config Sale configuration structure
     */
    function config() external view returns (Config memory) {
        return _config;
    }

    /**
     * @notice Get the project information
     * @return ProjectInfo Project information structure
     */
    function projectInfo() external view returns (ProjectInfo memory) {
        return _projectInfo;
    }

    /*///////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal function to finalize the token sale
     * @dev Marks sale as finalized and calls finishMinting on the token contract
     * @dev Emits SaleFinalized event
     */
    function _finalizeSale() internal {
        if (saleFinalized) revert SaleEnded();

        if (block.timestamp < _config.saleStart && tokensSold == 0)
            revert SaleNotActive();

        saleFinalized = true;
        projectToken.finishMinting();

        emit SaleFinalized(tokensSold);
    }

    /**
     * @dev Internal function to check if sale is currently active
     * @return bool True if sale meets all active conditions, false otherwise
     */
    function _isSaleActive() internal view returns (bool) {
        // Check various sale state conditions
        if (saleFinalized) return false;
        if (block.timestamp < _config.saleStart) return false;
        if (block.timestamp > _config.saleStart + _config.saleDuration)
            return false;
        if (tokensSold >= _config.totalTokens) return false;
        return true;
    }

    /*///////////////////////////////////////////////////////////////
                            FALLBACK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allow contract to receive ETH payments
     * @dev Required for ETH-based token purchases
     */
    receive() external payable {}
}
