// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IProjectVault
 * @notice Interface for the ProjectVault contract (V2)
 * @dev The Vault holds funds and releases them only when authorized.
 *      It contains NO business logic, governance, or milestone validation.
 */

interface IProjectVault {
    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Vault states
     * - Locked: Funds can be deposited, not released
     * - Active: Funds can be released
     * - Closed: Terminal state
     */
    enum VaultState {
        Locked,
        Active,
        Closed
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns the current state of the vault
     */
    function state() external view returns (VaultState);

    /**
     * @notice Returns the address of the associated project contract
     */
    function PROJECT() external view returns (address);

    /**
     * @notice Checks if a token is allowed for deposits
     */
    function isTokenAllowed(address token) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                            CORE ACTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Deposits tokens into the vault
     */
    function deposit(address token, uint256 amount) external;

    /**
     * @notice Activates the vault, allowing fund releases. Can only be called by the controller.
     */
    function activate() external;

    /**
     * @notice Closes the vault, preventing any further actions. Can only be called by governance.
     */
    function close() external;

    /**
     * @notice Releases funds from the vault to a specified address. Can only be called by the controller.
     */
    function release(address token, address to, uint256 amount) external;

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY CONTROL
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Pauses all vault operations. Can only be called by the guardian.
     */
    function pause() external;

    /**
     * @notice Unpauses vault operations. Can only be called by the guardian.
     */
    function unpause() external;
}
