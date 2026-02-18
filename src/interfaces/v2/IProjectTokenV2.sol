// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IProjectTokenV2
 * @notice Interface for the project governance token with supply caps and transfer controls.
 */
interface IProjectTokenV2 {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error TransfersDisabled();
    error MaxSupplyExceeded();
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event RevenueModuleSet(address indexed module);
    event TransfersEnabled();
    event Minted(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the token with name, symbol, and access control.
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param maxSupply_ Maximum total supply cap
     * @param admin_ Address with DEFAULT_ADMIN_ROLE
     * @param minter_ Address with MINTER_ROLE
     */
    function initialize(
        string calldata name_,
        string calldata symbol_,
        uint256 maxSupply_,
        address admin_,
        address minter_
    ) external;

    /**
     * @notice Mints new tokens to a specified address.
     * @param to Recipient of minted tokens
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Enables token transfers between non-zero addresses.
     * @dev Once enabled, transfers cannot be disabled.
     */
    function enableTransfers() external;

    /**
     * @notice Sets the revenue module for transfer hooks.
     * @param module Address of the revenue module contract
     */
    function setRevenueModule(address module) external;

    /**
     * @notice Returns the maximum total supply cap.
     * @return maxSupply Maximum supply
     */
    function maxSupply() external view returns (uint256);
}
