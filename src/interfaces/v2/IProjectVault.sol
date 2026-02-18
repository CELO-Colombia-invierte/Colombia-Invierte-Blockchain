// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IProjectVault
 * @notice Interface for the project vault that holds funds and enforces state transitions.
 */
interface IProjectVault {
    enum VaultState {
        Locked,
        Active,
        Closed
    }

    /*//////////////////////////////////////////////////////////////
                                VIEW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current state of the vault.
     * @return state Current VaultState (Locked, Active, Closed)
     */
    function state() external view returns (VaultState);

    /**
     * @notice Returns the project contract address associated with this vault.
     * @return project Address of the main project contract
     */
    function project() external view returns (address);

    /**
     * @notice Checks if a token is allowed for deposits.
     * @param token Token address to check
     * @return allowed True if token is on the allowlist
     */
    function isTokenAllowed(address token) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                                CORE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the vault with core contracts and roles.
     * @param project_ Address of the main project contract
     * @param governance_ Address that will manage state transitions
     * @param guardian_ Address that can pause and manage token allowlist
     */
    function initialize(
        address project_,
        address governance_,
        address guardian_
    ) external;

    /**
     * @notice Adds or removes a token from the deposit allowlist.
     * @param token Token address to configure
     * @param allowed True to allow deposits, false to block
     */
    function setTokenAllowed(address token, bool allowed) external;

    /**
     * @notice Deposits tokens on behalf of a user.
     * @param from Source address for the transfer
     * @param token Token address to deposit
     * @param amount Amount to deposit
     */
    function depositFrom(address from, address token, uint256 amount) external;

    /**
     * @notice Activates the vault, enabling fund releases.
     */
    function activate() external;

    /**
     * @notice Releases funds from the vault to a recipient.
     * @param token Token address to release
     * @param to Recipient address
     * @param amount Amount to release
     */
    function release(address token, address to, uint256 amount) external;

    /**
     * @notice Closes the vault, preventing further releases.
     */
    function close() external;

    /*//////////////////////////////////////////////////////////////
                                EMERGENCY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pauses all deposit and release operations.
     */
    function pause() external;

    /**
     * @notice Resumes normal operations after a pause.
     */
    function unpause() external;
}
