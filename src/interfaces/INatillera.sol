// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IPlatform} from "interfaces/IPlatform.sol";
import {ITracking} from "interfaces/ITracking.sol";

/**
 * @title INatillera
 * @author K-Labs
 * @notice Interface for Natillera project contracts
 * @dev Implements rotating savings and credit association (ROSCA) with 30-day cycles
 */
interface INatillera is ITracking {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configuration set by the project creator
     * @param token Address of the contribution token (address(0) for native)
     * @param monthlyContribution Monthly contribution per member
     * @param totalMonths Total number of contribution cycles
     * @param maxMembers Maximum number of members allowed
     */
    struct NatilleraConfig {
        address token;
        uint256 monthlyContribution;
        uint256 totalMonths;
        uint256 maxMembers;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a member makes a deposit
     * @param member Member address
     * @param amount Amount deposited
     * @param cycles Number of cycles covered
     * @param isUpToDate Whether the member is up to date after deposit
     */
    event Deposit(
        address indexed member,
        uint256 amount,
        uint256 cycles,
        bool isUpToDate
    );

    /**
     * @notice Emitted when a new member is added
     * @param member New member address
     * @param addedAt Timestamp when added
     */
    event MemberAdded(address indexed member, uint256 addedAt);

    /**
     * @notice Emitted when the cycle advances
     * @param oldCycle Previous cycle number
     * @param newCycle New cycle number
     * @param dueDate Due date of new cycle
     */
    event CycleAdvanced(uint256 oldCycle, uint256 newCycle, uint256 dueDate);

    /**
     * @notice Emitted when natillera is initialized
     * @param projectId Project ID from platform
     * @param creator Creator address
     * @param startTimestamp Start timestamp
     * @param monthlyContribution Contribution amount per month
     * @param maxMembers Maximum members allowed
     */
    event NatilleraInitialized(
        uint256 indexed projectId,
        address creator,
        uint256 startTimestamp,
        uint256 monthlyContribution,
        uint256 maxMembers
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit amount does not match required contribution
    error Natillera_InvalidDeposit();

    /// @notice Payment exceeds the amount due
    error Natillera_OverPayment();

    /// @notice Caller is not a member
    error Natillera_NotMember();

    /// @notice Member already added
    error Natillera_AlreadyMember();

    /// @notice Invalid start timestamp
    error Natillera_InvalidStart();

    /// @notice Invalid configuration parameters
    error Natillera_InvalidConfig();

    /// @notice Invalid member address
    error Natillera_InvalidMember();

    /// @notice Maximum members reached
    error Natillera_MaxMembersReached();

    /// @notice Invalid number of cycles
    error Natillera_InvalidCycles();

    /// @notice Contract is paused
    error Natillera_ContractPaused();

    /// @notice Contract is not paused
    error Natillera_ContractNotPaused();

    /// @notice Invalid token address
    error Natillera_InvalidToken();

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the natillera instance
     * @dev Can only be called once
     * @param startTimestamp Start timestamp (first due date)
     * @param natilleraConfig Configuration of the natillera
     * @param governanceConfig Governance configuration (reserved)
     * @param projectConfig Project configuration provided by Platform
     */
    function initialize(
        uint256 startTimestamp,
        NatilleraConfig calldata natilleraConfig,
        IPlatform.GovernanceConfig calldata governanceConfig,
        IPlatform.ProjectConfig calldata projectConfig
    ) external;

    /*//////////////////////////////////////////////////////////////
                            CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tracks the contribution status of a member
     * @param member Member address
     * @return amountPaid Total amount paid
     * @return amountDue Amount still due
     * @return missedCycles Number of missed cycles
     */
    function trackContribution(
        address member
    )
        external
        returns (uint256 amountPaid, uint256 amountDue, uint256 missedCycles);

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROLLED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits contribution for the current cycle
     * @dev Must send exact monthly contribution amount
     */
    function depositSingleCycle() external payable;

    /**
     * @notice Deposits contribution for multiple cycles
     * @dev Must send exact monthly contribution * cycles amount
     * @param cycles Number of cycles to cover (1-12)
     */
    function depositMultipleCycles(uint256 cycles) external payable;

    /**
     * @notice Adds a new member to the natillera
     * @dev Only owner can add members
     * @dev Cannot exceed maximum member limit
     * @param member Address to add
     */
    function addMember(address member) external;

    /*//////////////////////////////////////////////////////////////
                            EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pauses the natillera, stopping deposits and member additions
     * @dev Only owner can pause
     */
    function pause() external;

    /**
     * @notice Unpauses the natillera, resuming normal operations
     * @dev Only owner can unpause
     */
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Current cycle number
     */
    function cycle() external view returns (uint256);

    /**
     * @notice Due date of the current cycle
     */
    function cycleDueDate() external view returns (uint256);

    /**
     * @notice List of natillera members
     */
    function members() external view returns (address[] memory);

    /**
     * @notice Natillera configuration
     */
    function config() external view returns (NatilleraConfig memory);

    /**
     * @notice Returns deposit balance for a member
     * @param member Member address
     * @return Deposit balance
     */
    function getDepositBalance(address member) external view returns (uint256);

    /**
     * @notice Checks if an address is a member
     * @param account Address to check
     * @return True if member, false otherwise
     */
    function isMember(address account) external view returns (bool);

    /**
     * @notice Returns total number of members
     * @return Member count
     */
    function memberCount() external view returns (uint256);

    /**
     * @notice Returns platform contract address
     * @return Platform address
     */
    function platform() external view returns (address);

    /**
     * @notice Returns project ID assigned by platform
     * @return Project ID
     */
    function projectId() external view returns (uint256);
}
