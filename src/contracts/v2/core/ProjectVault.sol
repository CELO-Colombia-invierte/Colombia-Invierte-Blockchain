// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ProjectVault (V2)
 * @notice Single custody layer for V2 projects.
 * @dev Clonable via EIP-1167. Contains NO business logic.
 */
contract ProjectVault is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();
    error ZeroAmount();
    error InvalidState();
    error TokenNotAllowed();
    error InsufficientBalance();
    error VaultNotActive();
    error VaultNotLocked();

    /*//////////////////////////////////////////////////////////////
                                ROLES
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    enum VaultState {
        Locked,
        Active,
        Closed
    }

    VaultState public state;

    /// @notice Project contract wired post-clone
    address public project;

    mapping(address => bool) public isTokenAllowed;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event VaultInitialized(address indexed project, address indexed governance);
    event Deposited(
        address indexed token,
        address indexed from,
        uint256 amount
    );
    event Activated();
    event Released(address indexed token, address indexed to, uint256 amount);
    event Closed();
    event TokenAllowed(address indexed token, bool allowed);

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    function initialize(
        address project_,
        address governance_,
        address guardian_
    ) external initializer {
        if (
            project_ == address(0) ||
            governance_ == address(0) ||
            guardian_ == address(0)
        ) revert ZeroAddress();

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        project = project_;
        state = VaultState.Locked;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, governance_);
        _grantRole(GUARDIAN_ROLE, guardian_);
        _grantRole(CONTROLLER_ROLE, project_);

        emit VaultInitialized(project_, governance_);
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    function setTokenAllowed(
        address token,
        bool allowed
    ) external onlyRole(GUARDIAN_ROLE) {
        isTokenAllowed[token] = allowed;
        emit TokenAllowed(token, allowed);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits tokens on behalf of a user
     * @dev Only callable by the project contract
     */
    function depositFrom(
        address from,
        address token,
        uint256 amount
    ) external whenNotPaused nonReentrant onlyRole(CONTROLLER_ROLE) {
        if (state != VaultState.Locked) revert VaultNotLocked();
        if (!isTokenAllowed[token]) revert TokenNotAllowed();
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransferFrom(from, address(this), amount);

        emit Deposited(token, from, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        STATE TRANSITIONS
    //////////////////////////////////////////////////////////////*/

    function activate() external onlyRole(GOVERNANCE_ROLE) {
        if (state != VaultState.Locked) revert InvalidState();

        state = VaultState.Active;
        emit Activated();
    }

    function close() external onlyRole(GOVERNANCE_ROLE) {
        if (state != VaultState.Active) revert InvalidState();

        state = VaultState.Closed;
        emit Closed();
    }

    /*//////////////////////////////////////////////////////////////
                            RELEASE
    //////////////////////////////////////////////////////////////*/

    function release(
        address token,
        address to,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyRole(GOVERNANCE_ROLE) {
        if (state != VaultState.Active) revert VaultNotActive();
        if (amount == 0) revert ZeroAmount();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance();

        IERC20(token).safeTransfer(to, amount);

        emit Released(token, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY CONTROL
    //////////////////////////////////////////////////////////////*/

    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(GOVERNANCE_ROLE) {
        _unpause();
    }
}
