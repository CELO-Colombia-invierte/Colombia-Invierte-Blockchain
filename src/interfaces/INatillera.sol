// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPlatform} from "interfaces/IPlatform.sol";
import {ITracking} from "interfaces/ITracking.sol";

/**
 * @title INatillera
 * @author K-Labs
 * @notice Interface for Savings Pool contracts implementing proportional distribution
 * @dev Pool-based savings model with monthly cycles and proportional final distribution
 */
interface INatillera is ITracking {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configuration parameters for a Natillera pool
     * @param token Address of the ERC20 token for contributions (address(0) for native ETH)
     * @param monthlyContribution Required monthly contribution per member
     * @param totalMonths Total duration of the savings pool in months
     * @param maxMembers Maximum number of members allowed in the pool
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
     * @param member Address of the depositing member
     * @param amount Total amount deposited
     * @param cycles Number of monthly cycles covered by this deposit
     * @param isUpToDate Whether the member is now fully up-to-date after this deposit
     */
    event Deposit(
        address indexed member,
        uint256 amount,
        uint256 cycles,
        bool isUpToDate
    );

    /**
     * @notice Emitted when a new member is added to the pool
     * @param member Address of the newly added member
     */
    event MemberAdded(address indexed member);

    /**
     * @notice Emitted when the pool advances to the next monthly cycle
     * @param oldCycle Previous cycle number
     * @param newCycle New cycle number
     * @param dueDate Due date for contributions in the new cycle
     */
    event CycleAdvanced(uint256 oldCycle, uint256 newCycle, uint256 dueDate);

    /**
     * @notice Emitted when multiple members are added in a batch
     * @param members Array of addresses of newly added members
     */
    event MembersAddedBatch(address[] members);

    /**
     * @notice Emitted when the savings pool is finalized
     * @param totalCollected Total amount of capital collected from all members
     * @param totalAvailable Total balance available for distribution (capital + yield)
     */
    event PoolFinalized(uint256 totalCollected, uint256 totalAvailable);

    /**
     * @notice Emitted when a member withdraws their proportional share
     * @param member Address of the withdrawing member
     * @param capitalShare Portion of capital returned to the member
     * @param yieldShare Portion of yield distributed to the member
     */
    event FundsWithdrawn(
        address indexed member,
        uint256 capitalShare,
        uint256 yieldShare
    );

    /**
     * @notice Emitted when external yield is deposited in native currency
     * @param depositor Address that deposited the yield (typically the owner)
     * @param amount Amount of yield deposited
     */
    event YieldDeposited(address indexed depositor, uint256 amount);

    /**
     * @notice Emitted when external yield is deposited in ERC20 tokens
     * @param depositor Address that deposited the yield
     * @param token Address of the ERC20 token used for yield
     * @param amount Amount of yield deposited
     */
    event YieldDepositedERC20(
        address indexed depositor,
        address indexed token,
        uint256 amount
    );

    /**
     * @notice Emitted when a member makes an overpayment that becomes credit
     * @param member Address of the member who overpaid
     * @param amount Amount converted to credit for future cycles
     */
    event OverpaymentDeposited(address indexed member, uint256 amount);

    /**
     * @notice Emitted when a member uses accumulated credit to pay for a cycle
     * @param member Address of the member using credit
     * @param amount Amount of credit used
     */
    event CreditUsed(address indexed member, uint256 amount);

    /**
     * @notice Emitted when a member executes an emergency withdrawal
     * @param member Address of the member withdrawing
     * @param amount Amount withdrawn in emergency
     */
    event EmergencyWithdrawal(address indexed member, uint256 amount);

    /**
     * @notice Emitted when ETH is received by the contract
     * @param sender Address that sent ETH
     * @param amount Amount of ETH received
     */
    event EtherReceived(address indexed sender, uint256 amount);

    /**
     * @notice Emitted when the Natillera contract is initialized
     * @param projectId Unique project identifier from the platform
     * @param creator Address of the pool creator
     * @param startTimestamp Timestamp when the pool starts accepting contributions
     * @param monthlyContribution Monthly contribution amount configured
     * @param maxMembers Maximum members allowed as configured
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

    /// @notice Deposit amount does not match expected contribution
    error InvalidDeposit();

    /// @notice Payment exceeds the maximum allowed amount
    error OverPayment();

    /// @notice Caller is not a member of the pool
    error NotMember();

    /// @notice Address is already a member of the pool
    error AlreadyMember();

    /// @notice Invalid start timestamp (in past or too far in future)
    error InvalidStart();

    /// @notice Invalid configuration parameters provided
    error InvalidConfig();

    /// @notice Invalid member address (zero address or contract itself)
    error InvalidMember();

    /// @notice Maximum number of members has been reached
    error MaxMembersReached();

    /// @notice Invalid number of cycles specified (zero or exceeds maximum)
    error InvalidCycles();

    /// @notice Contract is currently paused
    error ContractPaused();

    /// @notice Contract is not paused when it should be
    error ContractNotPaused();

    /// @notice Member has already claimed their withdrawal
    error AlreadyClaimed();

    /// @notice Insufficient credit available for the requested operation
    error InsufficientCredit();

    /// @notice Transfer of funds failed
    error TransferFailed();

    /// @notice No yield amount provided for deposit
    error NoYield();

    /// @notice Yield token does not match pool's contribution token
    error InvalidYieldToken();

    /// @notice Pool has been finalized and no longer accepts deposits
    error AlreadyFinalized();

    /// @notice Pool is not yet finalized
    error NotFinalized();

    /// @notice Pool owner has been active recently
    error OwnerActive();

    /// @notice Credit has expired and can no longer be used
    error CreditExpired();

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the Natillera savings pool
     * @dev Can only be called once per instance
     * @dev Sets up the pool configuration and initial state
     * @param startTimestamp Timestamp when the pool starts (first cycle begins)
     * @param natilleraConfig Configuration parameters for the pool
     * @param governanceConfig Governance parameters (reserved for future use)
     * @param projectConfig Project metadata provided by the Platform contract
     */
    function initialize(
        uint256 startTimestamp,
        NatilleraConfig calldata natilleraConfig,
        IPlatform.GovernanceConfig calldata governanceConfig,
        IPlatform.ProjectConfig calldata projectConfig
    ) external;

    /*//////////////////////////////////////////////////////////////
                            CORE CONTRIBUTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit contribution for a single monthly cycle
     * @dev Must send exactly the monthly contribution amount in native currency
     * @dev Automatically synchronizes the cycle before processing
     */
    function depositSingleCycle() external payable;

    /**
     * @notice Deposit contribution for multiple monthly cycles
     * @dev Must send exactly (monthlyContribution * cycles) in native currency
     * @param cycles Number of cycles to pay for (1 to MAX_ADVANCE_CYCLES)
     */
    function depositMultipleCycles(uint256 cycles) external payable;

    /**
     * @notice Deposit with overpayment that becomes credit for future cycles
     * @dev Excess payment above exact amount is stored as credit for the member
     * @dev Credits expire after 1 year
     * @param cycles Minimum number of cycles to cover with this payment
     */
    function depositWithOverpayment(uint256 cycles) external payable;

    /**
     * @notice Use accumulated credit to pay for a monthly cycle
     * @dev Requires sufficient credit balance to cover one monthly contribution
     * @dev Credits expire after 1 year from deposit
     */
    function useCreditForCycle() external;

    /**
     * @notice Deposit external yield earnings in native currency
     * @dev Only callable by the pool owner
     * @dev Yield is added to the pool for proportional distribution at maturity
     */
    function depositYield() external payable;

    /**
     * @notice Deposit external yield earnings in ERC20 tokens
     * @dev Only callable by the pool owner
     * @param amount Amount of ERC20 tokens to deposit as yield
     */
    function depositYieldERC20(uint256 amount) external;

    /*//////////////////////////////////////////////////////////////
                            ADMINISTRATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a new member to the savings pool
     * @dev Only callable by the pool owner
     * @dev Registers the member with the platform
     * @param member Address of the new member to add
     */
    function addMember(address member) external;

    /**
     * @notice Add multiple members in a single transaction
     * @dev Only callable by the pool owner
     * @dev More gas-efficient than adding members individually
     * @param members Array of addresses to add as members
     */
    function batchAddMembers(address[] calldata members) external;

    /**
     * @notice Finalize the savings pool, enabling withdrawals
     * @dev Only callable by the pool owner
     * @dev Also happens automatically when totalMonths is reached
     */
    function finalize() external;

    /**
     * @notice Pause the pool, preventing new deposits and member additions
     * @dev Only callable by the pool owner
     */
    function pause() external;

    /**
     * @notice Unpause the pool, resuming normal operations
     * @dev Only callable by the pool owner
     */
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                            MEMBER WITHDRAWAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraw proportional share after pool finalization
     * @dev Calculates capital share as exact deposit amount
     * @dev Calculates yield share as: (memberDeposit / totalCollected) * availableYield
     * @dev Can only be called once per member after finalization
     */
    function withdraw() external;

    /**
     * @notice Emergency withdrawal for members when owner is inactive
     * @dev Available after 90 days of owner inactivity
     * @dev WARNING: Reduces totalCollected, affecting proportional calculations for remaining members
     * @dev Withdraws only capital contributions (no yield)
     * @dev Intended as last resort when owner cannot finalize pool
     */
    function emergencyWithdraw() external;

    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the current cycle number
     * @return Current monthly cycle (0-indexed)
     */
    function cycle() external view returns (uint256);

    /**
     * @notice Get the due date for the current cycle
     * @return Timestamp when contributions for current cycle are due
     */
    function cycleDueDate() external view returns (uint256);

    /**
     * @notice Get list of all member addresses
     * @return Array of all member addresses
     */
    function members() external view returns (address[] memory);

    /**
     * @notice Get the pool configuration
     * @return Current NatilleraConfig struct
     */
    function config() external view returns (NatilleraConfig memory);

    /**
     * @notice Get total capital collected from all members
     * @return Total amount of contributions collected
     */
    function totalCollected() external view returns (uint256);

    /**
     * @notice Get total capital withdrawn by members
     * @return Total amount withdrawn from the pool
     */
    function totalWithdrawn() external view returns (uint256);

    /**
     * @notice Get total external yield deposited
     * @return Total amount of yield added to the pool
     */
    function totalYieldDeposited() external view returns (uint256);

    /**
     * @notice Get total yield distributed to members
     * @return Total amount of yield already distributed
     */
    function totalYieldDistributed() external view returns (uint256);

    /**
     * @notice Get credit balance for a member
     * @param member Address to check credit for
     * @return Amount of credit available for the member
     */
    function credits(address member) external view returns (uint256);

    /**
     * @notice Get deposit balance for a member
     * @param member Address to check balance for
     * @return Total amount deposited by the member
     */
    function depositBalance(address member) external view returns (uint256);

    /**
     * @notice Check if an address is a member
     * @param account Address to check
     * @return True if address is a member, false otherwise
     */
    function isMember(address account) external view returns (bool);

    /**
     * @notice Check if the pool has reached its duration
     * @return True if current cycle >= totalMonths, false otherwise
     */
    function hasEnded() external view returns (bool);

    /**
     * @notice Check if the pool is finalized
     * @return True if pool is finalized and ready for withdrawals
     */
    function finalized() external view returns (bool);

    /**
     * @notice Check if a member has claimed their withdrawal
     * @param member Address to check
     * @return True if member has already withdrawn, false otherwise
     */
    function rewardsClaimed(address member) external view returns (bool);

    /**
     * @notice Calculate proportional share for a member
     * @param member Address to calculate share for
     * @return capitalShare Member's exact capital deposit
     * @return yieldShare Member's proportional share of yield
     * @return totalShare Total share (capital + yield)
     */
    function calculateShare(
        address member
    )
        external
        view
        returns (uint256 capitalShare, uint256 yieldShare, uint256 totalShare);

    /**
     * @notice Check credit expiry for a member
     * @param member Address to check
     * @return expiryTimestamp Timestamp when credits expire (0 if no credits)
     */
    function creditExpiry(address member) external view returns (uint256);
}
