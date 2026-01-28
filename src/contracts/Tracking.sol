// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ITracking} from "interfaces/ITracking.sol";

/**
 * @title Tracking
 * @author K-Labs
 * @notice Base contract for project tracking and platform integration
 * @dev Abstract contract providing standardized project metadata and platform interaction
 * @dev Inherited by Natillera, Tokenizacion, and Platform contracts
 * @dev Implements initialization pattern with proper validation
 */
abstract contract Tracking is Initializable, ITracking {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Platform contract address
    address private _platform;

    /// @notice Project identifier assigned by platform
    uint256 private _projectId;

    /// @notice Project creator address
    address private _creator;

    /// @notice Flag indicating if project has been initialized
    bool private _initialized;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Modifier to restrict access to platform only
     */
    modifier onlyPlatform() {
        if (msg.sender != _platform) revert NotPlatform();
        _;
    }

    /**
     * @dev Modifier to ensure contract is not already initialized
     */
    modifier notInitialized() {
        if (_initialized) revert AlreadyInitialized();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal function to initialize project tracking
     * @param platform_ Platform contract address
     * @param projectId_ Project identifier
     * @param creator_ Project creator address
     * @dev Should be called in derived contract's initialize function
     */
    function __Tracking_init(
        address platform_,
        uint256 projectId_,
        address creator_
    ) internal onlyInitializing notInitialized {
        // Validate parameters
        if (platform_ == address(0)) revert InvalidPlatform();
        if (projectId_ == 0) revert InvalidProjectId();
        if (creator_ == address(0)) revert InvalidCreator();

        // Store project information
        _platform = platform_;
        _projectId = projectId_;
        _creator = creator_;
        _initialized = true;

        emit ProjectInitialized(projectId_, platform_, creator_);
    }

    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITracking
     */
    function platform() public view override returns (address) {
        return _platform;
    }

    /**
     * @inheritdoc ITracking
     */
    function projectId() public view override returns (uint256) {
        return _projectId;
    }

    /**
     * @inheritdoc ITracking
     */
    function creator() public view override returns (address) {
        return _creator;
    }

    /**
     * @inheritdoc ITracking
     */
    function isValidProject() external view override returns (bool) {
        return
            _initialized &&
            _platform != address(0) &&
            _projectId != 0 &&
            _creator != address(0);
    }

    /**
     * @inheritdoc ITracking
     */
    function getProjectInfo()
        external
        view
        override
        returns (address platformAddress, uint256 id, address creatorAddress)
    {
        return (_platform, _projectId, _creator);
    }

    /**
     * @inheritdoc ITracking
     */
    function validatePlatformCaller() external view override {
        if (msg.sender != _platform) revert NotPlatform();
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITracking
     */
    function updatePlatform(
        address newPlatform
    ) external override onlyPlatform {
        if (newPlatform == address(0)) revert InvalidPlatform();
        if (newPlatform == _platform) revert SamePlatform();

        address oldPlatform = _platform;
        _platform = newPlatform;

        emit PlatformUpdated(oldPlatform, newPlatform);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the current owner of the contract
     * @return The address of the current owner (project creator)
     */
    function _owner() internal view returns (address) {
        return _creator;
    }

    /**
     * @dev Checks if the caller is the owner (project creator)
     * @return True if caller is owner, false otherwise
     */
    function _isOwner() internal view returns (bool) {
        return msg.sender == _creator;
    }

    /**
     * @dev Requires that the caller is the owner
     * @dev Reverts with NotOwner error if caller is not owner
     */
    function _requireOwner() internal view {
        if (msg.sender != _creator) revert NotOwner();
    }

    /**
     * @dev Returns the current platform address
     * @return Platform contract address
     */
    function _platformAddress() internal view returns (address) {
        return _platform;
    }

    /**
     * @dev Returns the current project ID
     * @return Project identifier
     */
    function _projectIdentifier() internal view returns (uint256) {
        return _projectId;
    }

    /**
     * @dev Returns the project creator address
     * @return Creator address
     */
    function _projectCreator() internal view returns (address) {
        return _creator;
    }

    /**
     * @dev Checks if the caller is the platform contract
     * @return True if caller is platform, false otherwise
     */
    function _isPlatform() internal view returns (bool) {
        return msg.sender == _platform;
    }

    /**
     * @dev Requires that the caller is the platform contract
     * @dev Reverts with NotPlatform error if caller is not platform
     */
    function _requirePlatform() internal view {
        if (msg.sender != _platform) revert NotPlatform();
    }

    /**
     * @dev Checks if contract has been initialized
     * @return True if initialized, false otherwise
     */
    function _isInitialized() internal view returns (bool) {
        return _initialized;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE GAP
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev This empty reserved space is put in place to allow future versions
     * to add new variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
