// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title ITokenizacionV2
 * @notice Interface for token sale contracts (V2)
 */
interface ITokenizacionV2 {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sale configuration structure
     * @param paymentToken ERC20 token used for payment
     * @param pricePerToken Price per project token (in payment token decimals)
     * @param totalTokens Total tokens for sale (in project token units)
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
     * @param platform Address of the platform contract
     * @param projectId ID of the project being tokenized
     * @param creator Address of the project creator
     */

    struct ProjectInfo {
        address platform;
        uint256 projectId;
        address creator;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    //// @notice Emitted when tokens are purchased
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 paid);
    /// @notice Emitted when the sale is finalized
    event SaleFinalized(uint256 totalSold);

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Purchase project tokens during the sale
     * @param amount Amount of project tokens to purchase (in project token units)
     */
    function buyTokens(uint256 amount) external;

    /**
     * @notice Finalize the sale and transfer remaining tokens to the creator
     * @dev Can only be called by the creator after the sale duration has ended
     */
    function finalizeSale() external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Check if sale is currently active
     * @return bool True if sale is active, false otherwise
     */
    function isSaleActive() external view returns (bool);

    /**
     * @notice Get the number of remaining tokens available for purchase
     * @return uint256 Count of tokens still available in the sale
     */
    function remainingTokens() external view returns (uint256);

    /**
     * @notice Get the sale configuration parameters
     * @return Config Sale configuration structure
     */
    function config() external view returns (Config memory);

    /**
     * @notice Get the project information
     * @return ProjectInfo Project information structure
     */
    function projectInfo() external view returns (ProjectInfo memory);

    /**
     * @notice Get the address of the vault where funds are stored
     * @return address Address of the vault contract
     */
    function vault() external view returns (address);
}
