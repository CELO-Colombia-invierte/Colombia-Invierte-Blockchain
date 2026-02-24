// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ProjectVault (Final Production Version)
 * @notice Custody layer for V2 projects.
 * @dev Minimal, deterministic, non-upgradable logic via clones.
 * @author Key Lab Technical Team.
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
    event Closed();
    event Released(address indexed token, address indexed to, uint256 amount);
    event TokenAllowed(address indexed token, bool allowed);

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes vault with project, roles and allowed token.
     * @dev All addresses must be non-zero. Sets project as CONTROLLER.
     */
    function initialize(
        address project_,
        address governance_,
        address guardian_,
        address allowedToken_
    ) external initializer {
        if (
            project_ == address(0) ||
            governance_ == address(0) ||
            guardian_ == address(0) ||
            allowedToken_ == address(0)
        ) revert ZeroAddress();

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        project = project_;
        state = VaultState.Locked;

        _grantRole(DEFAULT_ADMIN_ROLE, governance_);
        _grantRole(GOVERNANCE_ROLE, governance_);
        _grantRole(GUARDIAN_ROLE, guardian_);
        _grantRole(CONTROLLER_ROLE, project_);

        isTokenAllowed[allowedToken_] = true;
        emit VaultInitialized(project_, governance_);
        emit TokenAllowed(allowedToken_, true);
    }

    /*//////////////////////////////////////////////////////////////
                            TOKEN CONFIG
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
     * @notice Deposits allowed tokens from a specified address.
     * @dev Only callable in Locked state by CONTROLLER.
     */
    function depositFrom(
        address from,
        address token,
        uint256 amount
    ) external whenNotPaused nonReentrant onlyRole(CONTROLLER_ROLE) {
        if (state != VaultState.Locked) revert InvalidState();
        if (!isTokenAllowed[token]) revert TokenNotAllowed();
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransferFrom(from, address(this), amount);
        emit Deposited(token, from, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        STATE TRANSITIONS
    //////////////////////////////////////////////////////////////*/

    function activate() external onlyRole(CONTROLLER_ROLE) {
        if (state != VaultState.Locked) revert InvalidState();
        state = VaultState.Active;
        emit Activated();
    }

    function close() external onlyRole(CONTROLLER_ROLE) {
        if (state == VaultState.Closed) revert InvalidState();
        state = VaultState.Closed;
        emit Closed();
    }

    /*//////////////////////////////////////////////////////////////
                            RELEASE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Releases funds when vault is Active.
     * @dev Reverts if amount exceeds balance.
     */
    function release(
        address token,
        address to,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyRole(CONTROLLER_ROLE) {
        if (state != VaultState.Active) revert InvalidState();
        if (amount == 0) revert ZeroAmount();
        if (amount > IERC20(token).balanceOf(address(this)))
            revert InsufficientBalance();

        IERC20(token).safeTransfer(to, amount);
        emit Released(token, to, amount);
    }

    /**
     * @notice Releases funds only when vault is Closed.
     * @dev For final settlements after project completion.
     */
    function releaseOnClose(
        address token,
        address to,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyRole(CONTROLLER_ROLE) {
        if (state != VaultState.Closed) revert InvalidState();
        if (amount == 0) revert ZeroAmount();
        if (amount > IERC20(token).balanceOf(address(this)))
            revert InsufficientBalance();

        IERC20(token).safeTransfer(to, amount);
        emit Released(token, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            EMERGENCY
    //////////////////////////////////////////////////////////////*/

    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(GOVERNANCE_ROLE) {
        _unpause();
    }
}
