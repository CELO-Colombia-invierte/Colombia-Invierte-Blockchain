// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {ITracking} from "interfaces/ITracking.sol";

/**
 * @title Tracking
 * @author K-Labs
 * @notice Base contract for project tracking and platform integration
 * @dev Abstract contract providing standardized project metadata and platform interaction
 * @dev Inherited by Natillera and Tokenizacion contracts
 * @dev Implements initialization pattern with proper validation
 */
abstract contract Tracking is Initializable, OwnableUpgradeable, ITracking {
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
        if (msg.sender != _platform) revert Tracking_NotPlatform();
        _;
    }

    /**
     * @dev Modifier to ensure contract is not already initialized
     */
    modifier notInitialized() {
        if (_initialized) revert Tracking_AlreadyInitialized();
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
    ) internal onlyInitializing {
        // Validate parameters
        if (platform_ == address(0)) revert Tracking_InvalidPlatform();
        if (projectId_ == 0) revert Tracking_InvalidProjectId();
        if (creator_ == address(0)) revert Tracking_InvalidPlatform();

        // Initialize Ownable with creator
        __Ownable_init(creator_);

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
     * @notice Returns the platform contract address
     */
    function platform() public view override returns (address) {
        return _platform;
    }

    /**
     * @inheritdoc ITracking
     * @notice Returns the project identifier
     */
    function projectId() public view override returns (uint256) {
        return _projectId;
    }

    /**
     * @inheritdoc ITracking
     * @notice Returns the project creator address
     */
    function creator() public view override returns (address) {
        return _creator;
    }

    /**
     * @inheritdoc ITracking
     * @notice Checks if the contract is a valid project registered with platform
     * @return True if project is properly registered, false otherwise
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
     * @notice Returns complete project metadata
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
     * @notice Validates that caller is the platform contract
     * @dev Reverts with Tracking_NotPlatform if caller is not platform
     */
    function validatePlatformCaller() external view override {
        if (msg.sender != _platform) revert Tracking_NotPlatform();
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ITracking
     * @notice Updates the platform reference (emergency use only)
     * @dev Only callable by current platform
     * @param newPlatform New platform contract address
     */
    function updatePlatform(
        address newPlatform
    ) external override onlyPlatform {
        if (newPlatform == address(0)) revert Tracking_InvalidPlatform();
        if (newPlatform == _platform) revert Tracking_PlatformImmutable();

        address oldPlatform = _platform;
        _platform = newPlatform;

        emit PlatformUpdated(oldPlatform, newPlatform);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal function to get platform address (for derived contracts)
     * @return Current platform address
     */
    function _getPlatform() internal view returns (address) {
        return _platform;
    }

    /**
     * @dev Internal function to get project ID (for derived contracts)
     * @return Current project ID
     */
    function _getProjectId() internal view returns (uint256) {
        return _projectId;
    }

    /**
     * @dev Internal function to get creator address (for derived contracts)
     * @return Project creator address
     */
    function _getCreator() internal view returns (address) {
        return _creator;
    }

    /**
     * @dev Internal function to check if caller is platform
     * @return True if caller is platform, false otherwise
     */
    function _isPlatform() internal view returns (bool) {
        return msg.sender == _platform;
    }

    /**
     * @dev Internal function to require platform caller
     * @dev Reverts if caller is not platform
     */
    function _requirePlatform() internal view {
        if (msg.sender != _platform) revert Tracking_NotPlatform();
    }

    /**
     * @dev Internal function to check if contract is initialized
     * @return True if initialized, false otherwise
     */
    function _isInitialized() internal view returns (bool) {
        return _initialized;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions
     * to add new variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
