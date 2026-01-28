// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title ITracking
 * @author K-Labs
 * @notice Interface for project tracking metadata and platform integration
 * @dev Base interface for all project contracts (Natillera, Tokenizacion)
 * @dev Provides standardized access to platform information and project identification
 */
interface ITracking {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when project is initialized with platform
     * @param projectId Unique project identifier assigned by platform
     * @param platformAddress Address of the platform contract
     * @param creator Address of the project creator
     */
    event ProjectInitialized(
        uint256 indexed projectId,
        address indexed platformAddress,
        address indexed creator
    );

    /**
     * @notice Emitted when platform reference is updated
     * @param oldPlatform Previous platform address
     * @param newPlatform New platform address
     */
    event PlatformUpdated(
        address indexed oldPlatform,
        address indexed newPlatform
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Invalid platform address (zero address)
    error InvalidPlatform();

    /// @notice Invalid project ID (zero)
    error InvalidProjectId();

    /// @notice Invalid creator address (zero address)
    error InvalidCreator();

    /// @notice Caller is not the platform
    error NotPlatform();

    /// @notice Caller is not the owner
    error NotOwner();

    /// @notice Project already initialized
    error AlreadyInitialized();

    /// @notice Platform address cannot be changed to same value
    error SamePlatform();

    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the platform contract address
     * @return platformAddress Address of the platform contract
     */
    function platform() external view returns (address platformAddress);

    /**
     * @notice Returns the project identifier
     * @return id Unique project ID assigned by the platform
     */
    function projectId() external view returns (uint256 id);

    /**
     * @notice Returns the project creator address
     * @return creator Address that created the project
     */
    function creator() external view returns (address creator);

    /**
     * @notice Checks if the contract is a valid project registered with platform
     * @return isValid True if project is properly registered, false otherwise
     */
    function isValidProject() external view returns (bool isValid);

    /**
     * @notice Returns project metadata
     * @return platformAddress Platform contract address
     * @return id Project identifier
     * @return creatorAddress Project creator address
     */
    function getProjectInfo()
        external
        view
        returns (address platformAddress, uint256 id, address creatorAddress);

    /**
     * @notice Validates that caller is the platform contract
     * @dev Reverts with NotPlatform if not called by platform
     */
    function validatePlatformCaller() external view;

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the platform reference (emergency use only)
     * @dev Only callable by current platform
     * @dev Should only be used for platform migration scenarios
     * @param newPlatform New platform contract address
     */
    function updatePlatform(address newPlatform) external;
}
