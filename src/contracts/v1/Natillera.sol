// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {INatillera} from "../../interfaces/v1/INatillera.sol";

/**
 * @title Natillera
 * @notice Savings pool with monthly contributions
 * @dev MVP V1: Members contribute monthly, receive proportional share at maturity
 * @dev Note: Members who don't contribute can still withdraw 0 (no penalty mechanism)
 * @dev Future versions may implement minimum contribution requirements
 */
contract Natillera is Ownable, ReentrancyGuard, INatillera {
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Seconds in a month (30 days)
    uint256 private constant SECONDS_PER_MONTH = 30 days;

    /// @notice Minimum pool duration (3 months)
    uint256 private constant MIN_TOTAL_MONTHS = 3;

    /// @notice Maximum pool duration (60 months)
    uint256 private constant MAX_TOTAL_MONTHS = 60;

    /// @notice Maximum members per pool
    uint256 private constant MAX_MEMBERS = 100;

    /*///////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether contract is initialized
    bool private _initialized;

    /// @notice Pool configuration
    Config private _config;

    /// @notice Project information
    ProjectInfo private _projectInfo;

    /// @notice When contributions start
    uint256 public startTime;

    /// @notice Current cycle (0-indexed)
    uint256 public currentCycle;

    /// @notice When current cycle ends
    uint256 public cycleEndTime;

    /// @notice Whether pool is finalized
    bool public isFinalized;

    /// @notice Total contributions collected
    uint256 public totalCollected;

    /// @notice Final balance at pool finalization
    uint256 public finalBalance;

    /// @notice Member addresses array
    address[] private _members;

    /// @notice Mapping of membership status per address
    mapping(address => bool) public isMember;

    /// @notice Mapping of total deposits per member
    mapping(address => uint256) public deposits;

    /// @notice Mapping of last paid cycle per member
    mapping(address => uint256) private _lastPaidCycle;

    /// @notice Mapping of withdrawal status per member
    mapping(address => bool) private _hasWithdrawn;

    /*///////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Modifier to restrict access to pool members only
     * @notice Reverts with NotMember error if caller is not a member
     */
    modifier onlyMember() {
        _onlyMember();
        _;
    }

    /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Disable direct deployment
     * @dev Contract must be deployed via Platform factory
     */
    constructor() Ownable(msg.sender) {
        // owner will be replaced in initialize()
    }

    /*///////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the savings pool with configuration and parameters
     * @param startTime_ Timestamp when contributions start
     * @param config_ Pool configuration parameters
     * @param info_ Project information
     * @dev Can only be called once per pool instance
     * @dev Transfers ownership to the project creator
     */
    function initialize(
        uint256 startTime_,
        Config calldata config_,
        ProjectInfo calldata info_
    ) external {
        // Ensure single initialization
        if (_initialized) revert AlreadyInitialized();

        // Validate configuration parameters
        if (config_.token == address(0)) revert InvalidToken();
        if (config_.monthlyContribution == 0) revert InvalidAmount();
        if (config_.totalMonths < MIN_TOTAL_MONTHS) revert InvalidAmount();
        if (config_.totalMonths > MAX_TOTAL_MONTHS) revert InvalidAmount();
        if (config_.maxMembers == 0 || config_.maxMembers > MAX_MEMBERS)
            revert InvalidAmount();
        if (startTime_ <= block.timestamp) revert InvalidAmount();
        if (startTime_ > block.timestamp + 365 days) revert InvalidAmount();

        // Store configuration and state
        _config = config_;
        _projectInfo = info_;
        startTime = startTime_;
        currentCycle = 0;
        cycleEndTime = startTime_ + SECONDS_PER_MONTH;
        _initialized = true;

        // Set creator's last paid cycle to max (exempt from payments)
        _lastPaidCycle[info_.creator] = type(uint256).max;

        // Transfer ownership to creator
        _transferOwnership(info_.creator);

        // Add creator as first member
        _addMember(info_.creator);
    }

    /*///////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Make monthly contribution for current cycle
     * @dev Transfers monthly contribution amount from member to contract
     * @dev Updates member's deposit total and last paid cycle
     * @dev Automatically updates cycle if needed
     * @dev Emits Deposit event
     */
    function deposit() external onlyMember nonReentrant {
        // Update cycle based on current timestamp
        _updateCycle();

        // Validate state conditions
        if (isFinalized) revert PoolEnded();
        if (currentCycle >= _config.totalMonths) revert PoolEnded();
        if (_lastPaidCycle[msg.sender] == currentCycle) revert AlreadyPaid();

        uint256 amount = _config.monthlyContribution;

        // Transfer tokens from member to contract
        IERC20(_config.token).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        // Update member and pool state
        deposits[msg.sender] += amount;
        totalCollected += amount;
        _lastPaidCycle[msg.sender] = currentCycle;

        emit Deposit(msg.sender, amount, currentCycle);
    }

    /**
     * @notice Add new member to the savings pool
     * @param member Address to add as a member
     * @dev Can only be called by pool owner (creator)
     * @dev Can only add members before pool is finalized
     * @dev Emits MemberAdded event
     */
    function addMember(address member) external onlyOwner {
        // Validate state conditions
        if (isFinalized) revert PoolEnded();
        if (isMember[member]) revert AlreadyMember();
        if (_members.length >= _config.maxMembers) revert MaxMembersReached();

        _addMember(member);
    }

    /**
     * @notice Withdraw proportional share after finalization
     * @dev Calculates share based on member's total deposits vs total collected
     * @dev Transfers proportional share of current pool balance to member
     * @dev Can only withdraw once per member
     * @dev Emits Withdrawn event
     */
    function withdraw() external onlyMember nonReentrant {
        if (!isFinalized) revert NotFinalized();
        if (_hasWithdrawn[msg.sender]) revert AlreadyWithdrawn();

        uint256 memberDeposit = deposits[msg.sender];
        if (memberDeposit == 0) revert InvalidAmount();

        // Calculate proportional share of current pool balance
        uint256 share = (memberDeposit * finalBalance) / totalCollected;

        // Update withdrawal status
        _hasWithdrawn[msg.sender] = true;

        // Transfer proportional share to member
        IERC20(_config.token).safeTransfer(msg.sender, share);

        emit Withdrawn(msg.sender, share);
    }

    /**
     * @notice Finalize the pool if duration has ended
     * @dev Can be called by anyone
     */
    function finalize() external override {
        if (!hasEnded()) revert NotFinalized();

        if (!isFinalized) {
            isFinalized = true;
            finalBalance = IERC20(_config.token).balanceOf(address(this));
            emit PoolFinalized(finalBalance);
        }
    }

    /*///////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if pool has reached its total duration
     * @return bool True if pool duration has ended, false otherwise
     */
    function hasEnded() public view returns (bool) {
        return
            block.timestamp >=
            startTime + (_config.totalMonths * SECONDS_PER_MONTH);
    }

    /**
     * @notice Get all member addresses
     * @return address[] memory Array of all member addresses
     */
    function members() external view returns (address[] memory) {
        return _members;
    }

    /**
     * @notice Calculate member's proportional share (for UI display)
     * @param member Address of member to calculate share for
     * @return uint256 Member's proportional share of pool balance
     * @dev Returns 0 if pool not finalized or member has no deposits
     */
    function calculateShare(address member) external view returns (uint256) {
        if (!isFinalized || deposits[member] == 0) return 0;

        return (deposits[member] * finalBalance) / totalCollected;
    }

    /**
     * @notice Get the sale configuration parameters
     * @return Config Sale configuration structure
     */
    function config() external view returns (Config memory) {
        return _config;
    }

    /**
     * @notice Get the project information
     * @return ProjectInfo Project information structure
     */
    function projectInfo() external view returns (ProjectInfo memory) {
        return _projectInfo;
    }

    /*///////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal function to check if caller is a member
     * @dev Reverts with NotMember error if caller is not a member
     */
    function _onlyMember() internal view {
        if (!isMember[msg.sender]) revert NotMember();
    }

    /**
     * @dev Internal function to add member to pool
     * @param member Address to add as member
     * @dev Updates membership mapping and array
     * @dev Emits MemberAdded event
     */
    function _addMember(address member) internal {
        isMember[member] = true;
        _lastPaidCycle[member] = type(uint256).max;
        _members.push(member);
        emit MemberAdded(member);
    }

    /**
     * @dev Internal function to update current cycle based on timestamp
     * @dev Automatically advances cycles if time has passed
     * @dev Auto-finalizes pool if duration is reached
     */
    function _updateCycle() internal {
        // Check if current cycle has ended
        if (block.timestamp <= cycleEndTime) return;

        // Calculate number of cycles passed since last update
        uint256 cyclesPassed = (block.timestamp - cycleEndTime) /
            SECONDS_PER_MONTH +
            1;
        uint256 newCycle = currentCycle + cyclesPassed;

        // Update cycle state if needed
        if (newCycle > currentCycle) {
            currentCycle = newCycle;
            cycleEndTime += cyclesPassed * SECONDS_PER_MONTH;

            // Auto-finalize if pool duration is reached
            if (currentCycle >= _config.totalMonths && !isFinalized) {
                isFinalized = true;
                finalBalance = IERC20(_config.token).balanceOf(address(this));
                emit PoolFinalized(finalBalance);
            }
        }
    }
}
