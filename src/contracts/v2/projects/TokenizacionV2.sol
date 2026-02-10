// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITokenizacionV2} from "../../../interfaces/v2/ITokenizacionV2.sol";
import {IProjectVault} from "../../../interfaces/v2/IProjectVault.sol";

/**
 * @title TokenizacionV2
 * @notice Token sale contract that deposits funds into a ProjectVault
 * @dev V2: No fund custody, no withdrawals, no governance
 */
contract TokenizacionV2 is ITokenizacionV2, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    /// @notice The operation is not allowed in the current state
    error SaleNotActive();
    /// @notice The token sale has already ended
    error SaleEnded();
    /// @notice The provided amount is invalid (e.g., zero)
    error InvalidAmount();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice Configuration for the token sale
    Config private _config;
    /// @notice Information about the project
    ProjectInfo private _projectInfo;
    /// @notice Address of the ProjectVault where funds are deposited
    address public immutable vault;
    /// @notice Total tokens sold so far
    uint256 public tokensSold;
    /// @notice Whether the sale has been finalized
    bool public saleFinalized;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Constructor for the Tokenization contract
     * @param config_ Configuration for the token sale
     * @param info_ Information about the project
     * @param vault_ Address of the ProjectVault where funds will be deposited
     */
    constructor(
        Config memory config_,
        ProjectInfo memory info_,
        address vault_
    ) {
        _config = config_;
        _projectInfo = info_;
        vault = vault_;
    }

    /*//////////////////////////////////////////////////////////////
                            CORE LOGIC
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Buy tokens for a specified amount
     * @param amount Number of tokens to purchase
     */
    function buyTokens(uint256 amount) external nonReentrant {
        if (!_isSaleActive()) revert SaleNotActive();
        if (amount == 0) revert InvalidAmount();
        if (tokensSold + amount > _config.totalTokens) revert SaleEnded();

        uint256 cost = amount * _config.pricePerToken;

        IERC20(_config.paymentToken).safeTransferFrom(
            msg.sender,
            address(this),
            cost
        );

        IERC20(_config.paymentToken).safeIncreaseAllowance(
            address(vault),
            cost
        );

        IProjectVault(vault).deposit(_config.paymentToken, cost);

        tokensSold += amount;

        emit TokensPurchased(msg.sender, amount, cost);

        if (tokensSold == _config.totalTokens) {
            _finalize();
        }
    }

    /**
     * @notice Finalize the token sale and activate the ProjectVault
     * @dev Can only be called when the sale is active and not already finalized
     */
    function finalizeSale() external {
        if (!_isSaleActive()) revert SaleNotActive();
        _finalize();
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Check if the token sale is currently active
     * @return True if the sale is active, false otherwise
     */
    function isSaleActive() external view returns (bool) {
        return _isSaleActive();
    }

    /**
     * @notice Get the number of remaining tokens available for sale
     * @return Number of remaining tokens
     */
    function remainingTokens() external view returns (uint256) {
        return _config.totalTokens - tokensSold;
    }

    /**
     * @notice Get the configuration parameters for the token sale
     * @return Config The configuration parameters
     */
    function config() external view returns (Config memory) {
        return _config;
    }

    /**
     * @notice Get the information about the project
     * @return ProjectInfo The project information
     */
    function projectInfo() external view returns (ProjectInfo memory) {
        return _projectInfo;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Finalize the token sale and activate the ProjectVault
     * @dev Can only be called when the sale is active and not already finalized
     */
    function _finalize() internal {
        saleFinalized = true;
        IProjectVault(vault).activate();
        emit SaleFinalized(tokensSold);
    }

    /**
     * @dev Check if the token sale is currently active based on time and finalization status
     * @return True if the sale is active, false otherwise
     */
    function _isSaleActive() internal view returns (bool) {
        if (saleFinalized) return false;
        if (block.timestamp < _config.saleStart) return false;
        if (block.timestamp > _config.saleStart + _config.saleDuration)
            return false;
        return true;
    }
}
