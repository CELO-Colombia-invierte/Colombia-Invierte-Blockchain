// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IProjectVault
 * @notice Interface for the project vault that holds funds and enforces state transitions.
 * @author Key Lab Technical Team.
 */
interface IProjectVault {
    enum VaultState {
        Locked,
        Active,
        Closed
    }

    /*//////////////////////////////////////////////////////////////
                                CORE
    //////////////////////////////////////////////////////////////*/

    function initialize(
        address project_,
        address governance_,
        address guardian_,
        address allowedToken_
    ) external;

    function setTokenAllowed(address token, bool allowed) external;

    function depositFrom(address from, address token, uint256 amount) external;

    function activate() external;

    function release(address token, address to, uint256 amount) external;

    function releaseOnClose(address token, address to, uint256 amount) external;

    function close() external;

    /*//////////////////////////////////////////////////////////////
                                VIEW
    //////////////////////////////////////////////////////////////*/

    function state() external view returns (VaultState);

    function project() external view returns (address);

    function isTokenAllowed(address token) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                                EMERGENCY
    //////////////////////////////////////////////////////////////*/

    function pause() external;

    function unpause() external;
}
