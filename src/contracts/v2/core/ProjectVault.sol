// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ProjectVault
 * @notice Custody contract for project funds (V2)
 * @dev The Vault holds funds and releases them only when authorized.
 *      It contains NO business logic, governance, or milestone validation.
 */
contract ProjectVault is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    /// @notice The operation is not allowed in the current state
    error InvalidState();
    /// @notice The specified token is not allowed for deposits
    error TokenNotAllowed();
    /// @notice The specified amount is zero
    error ZeroAmount();
    /// @notice The vault has insufficient balance for the requested release
    error InsufficientBalance();
    /// @notice The specified address is zero
    error ZeroAddress();
    /// @notice The vault is currently locked and cannot perform the operation
    error VaultLocked();
    /// @notice The vault is currently active and cannot perform the operation
    error VaultNotActive();
    /// @notice The vault is closed and cannot perform the operation
    error VaultClosed();

    /*//////////////////////////////////////////////////////////////
                                ROLES
    //////////////////////////////////////////////////////////////*/
    /// @notice Role identifier for the controller (project contract)
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    /// @notice Role identifier for governance actions
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    /// @notice Role identifier for emergency guardian
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

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
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Current vault state
    VaultState public state;

    /// @notice Project contract controlling this vault (NatilleraV2 / TokenizacionV2)
    address public immutable PROJECT;

    /// @notice Whitelisted ERC20 tokens
    mapping(address => bool) public isTokenAllowed;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Emitted when tokens are deposited into the vault
     */
    event Deposited(
        address indexed token,
        address indexed from,
        uint256 amount
    );
    /**
     * @notice Emitted when the vault is activated
     */
    event Activated();
    /**
     * @notice Emitted when tokens are released from the vault
     */
    event Released(address indexed token, address indexed to, uint256 amount);
    /**
     * @notice Emitted when the vault is closed
     */
    event Closed();
    /**
     * @notice Emitted when a token's allowed status is changed
     */
    event TokenAllowed(address indexed token, bool allowed);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param project_ Address of the controlling project contract
     * @param admin Address receiving DEFAULT_ADMIN_ROLE
     */
    constructor(address project_, address admin) {
        if (project_ == address(0) || admin == address(0)) revert ZeroAddress();
        PROJECT = project_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONTROLLER_ROLE, project_);
        _grantRole(GOVERNANCE_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, admin);

        state = VaultState.Locked;
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allow or disallow a token for deposits
     * @dev Governance-controlled
     */
    function setTokenAllowed(
        address token,
        bool allowed
    ) external onlyRole(GOVERNANCE_ROLE) {
        isTokenAllowed[token] = allowed;
        emit TokenAllowed(token, allowed);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit ERC20 tokens into the vault
     * @dev Only allowed while state == Locked
     */
    function deposit(
        address token,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        if (state != VaultState.Locked) revert VaultClosed();
        if (!isTokenAllowed[token]) revert TokenNotAllowed();
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(token, msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        STATE TRANSITIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Activate the vault (Locked → Active)
     * @dev Callable once by controller
     */
    function activate() external onlyRole(CONTROLLER_ROLE) {
        if (state != VaultState.Locked) revert VaultClosed();

        state = VaultState.Active;
        emit Activated();
    }

    /**
     * @notice Permanently close the vault
     * @dev Terminal state
     */
    function close() external onlyRole(GOVERNANCE_ROLE) {
        if (state != VaultState.Active) revert InvalidState();

        state = VaultState.Closed;
        emit Closed();
    }

    /*//////////////////////////////////////////////////////////////
                        FUNDS RELEASE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Release funds to a recipient
     * @dev Governance-controlled execution only
     */
    function release(
        address token,
        address to,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyRole(CONTROLLER_ROLE) {
        if (state != VaultState.Active) revert VaultNotActive();
        if (amount == 0) revert ZeroAmount();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance();

        IERC20(token).safeTransfer(to, amount);

        emit Released(token, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        DISPUTE RESOLUTION
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Check if an account can resolve disputes
     * @dev Only accounts with GOVERNANCE_ROLE can resolve disputes
     */
    function canResolveDispute(address account) external view returns (bool) {
        return hasRole(GOVERNANCE_ROLE, account);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY CONTROL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pause vault operations
     * @dev Emergency guardian
     */
    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause vault operations
     * @dev Governance-controlled
     */
    function unpause() external onlyRole(GOVERNANCE_ROLE) {
        _unpause();
    }
}
