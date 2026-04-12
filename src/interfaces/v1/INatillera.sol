// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title INatillera
 * @notice Interface for savings pool with monthly contributions
 * @dev MVP V1: Simple pool where members contribute monthly, receive proportional share at maturity
 */
interface INatillera {
  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Pool configuration structure
   * @param token ERC20 token for contributions (stablecoin)
   * @param monthlyContribution Monthly amount per member (in token decimals)
   * @param totalMonths Total duration in months
   * @param maxMembers Maximum number of members allowed
   */
  struct Config {
    address token;
    uint256 monthlyContribution;
    uint256 totalMonths;
    uint256 maxMembers;
  }

  /**
   * @notice Project information structure
   * @param platform Platform contract address
   * @param projectId Unique project identifier
   * @param creator Project creator address
   */
  struct ProjectInfo {
    address platform;
    uint256 projectId;
    address creator;
  }

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice Error emitted when the caller is not a member of the pool
  error NotMember();
  /// @notice Error emitted when trying to add an address that is already a member
  error AlreadyMember();
  /// @notice Error emitted when a member tries to pay for a cycle they've already paid
  error AlreadyPaid();
  /// @notice Error emitted when trying to perform an action after the pool has ended
  error PoolEnded();
  /// @notice Error emitted when trying to add more members than the maximum allowed
  error MaxMembersReached();
  /// @notice Error emitted when trying to withdraw before the pool is finalized
  error NotFinalized();
  /// @notice Error emitted when a member tries to withdraw after already withdrawing their share
  error AlreadyWithdrawn();
  /// @notice Error emitted when an invalid token address is provided
  error InvalidToken();
  /// @notice Error emitted when an invalid contribution amount is provided
  error InvalidAmount();
  /// @notice Error emitted when trying to initialize an already initialized pool
  error AlreadyInitialized();

  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Event emitted when a member makes a monthly deposit
   * @param member Address of the member who deposited
   * @param amount Amount deposited (in token decimals)
   * @param cycle Current contribution cycle (month)
   * @dev Emitted in the `deposit()` function
   */
  event Deposit(address indexed member, uint256 amount, uint256 cycle);

  /**
   * @notice Event emitted when a new member is added to the pool
   * @param member Address of the newly added member
   * @dev Emitted in the `addMember()` function
   */
  event MemberAdded(address indexed member);

  /**
   * @notice Event emitted when the pool is finalized and withdrawals are enabled
   * @param totalCollected Total amount collected in the pool (in token decimals)
   * @dev Emitted in the `finalize()` function
   */
  event PoolFinalized(uint256 totalCollected);

  /**
   * @notice Event emitted when a member withdraws their proportional share
   * @param member Address of the member who withdrew
   * @param amount Amount withdrawn (in token decimals)
   * @dev Emitted in the `withdraw()` function
   */
  event Withdrawn(address indexed member, uint256 amount);

  /*///////////////////////////////////////////////////////////////
                          INITIALIZATION
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Initialize the savings pool with configuration and project info
   * @param startTime Timestamp when contributions start
   * @param config_ Pool configuration parameters
   * @param info_ Project information
   * @dev Can only be called once per pool instance
   */
  function initialize(uint256 startTime, Config calldata config_, ProjectInfo calldata info_) external;

  /*///////////////////////////////////////////////////////////////
                          CORE FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Make monthly contribution for the current cycle
   * @dev Transfers `monthlyContribution` amount from caller to contract
   *      Can only be called by pool members during active contribution period
   */
  function deposit() external;

  /**
   * @notice Add a new member to the savings pool
   * @param member Address to add as a member
   * @dev Can only be called by the pool creator before the pool starts
   */
  function addMember(address member) external;

  /**
   * @notice Finalize the pool and enable withdrawals
   * @dev Can only be called after all contribution cycles are complete
   *      Calculates each member's proportional share of the total collected
   */
  function finalize() external;

  /**
   * @notice Withdraw proportional share after finalization
   * @dev Transfers caller's share of the total collected pool funds
   *      Can only be called by members after pool finalization
   */
  function withdraw() external;

  /*///////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Get the pool configuration
   * @return Config memory Pool configuration structure
   */
  function config() external view returns (Config memory);

  /**
   * @notice Get the current contribution cycle (month)
   * @return uint256 Current cycle number (0-indexed)
   */
  function currentCycle() external view returns (uint256);

  /**
   * @notice Check if an address is a member of the pool
   * @param account Address to check
   * @return bool True if address is a member, false otherwise
   */
  function isMember(address account) external view returns (bool);

  /**
   * @notice Get the total amount deposited by a specific member
   * @param member Member address
   * @return uint256 Total amount deposited by the member (in token decimals)
   */
  function deposits(address member) external view returns (uint256);

  /**
   * @notice Check if the pool has been finalized
   * @return bool True if pool is finalized, false otherwise
   */
  function isFinalized() external view returns (bool);

  /**
   * @notice Get the total amount collected in the pool
   * @return uint256 Total collected amount (in token decimals)
   */
  function totalCollected() external view returns (uint256);

  /**
   * @notice Check if the pool has ended (all cycles completed)
   * @return bool True if pool has ended, false otherwise
   */
  function hasEnded() external view returns (bool);

  /**
   * @notice Get all member addresses
   * @return address[] memory Array of all member addresses
   */
  function members() external view returns (address[] memory);

  /**
   * @notice Get the project information
   * @return ProjectInfo memory Project information structure
   */
  function projectInfo() external view returns (ProjectInfo memory);
}
