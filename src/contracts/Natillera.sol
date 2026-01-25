// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Tracking} from "contracts/Tracking.sol";
import {CycleMath} from "contracts/libraries/CycleMath.sol";
import {INatillera} from "interfaces/INatillera.sol";
import {IPlatform} from "interfaces/IPlatform.sol";

/**
 * @title Natillera
 * @dev Savings pool contract implementing rotating savings and credit association
 * @notice Members make regular monthly contributions in 30-day cycles
 * @author K-Labs
 * @dev Uses upgradeable pattern for potential future improvements
 */
contract Natillera is
    Initializable,
    Tracking,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    INatillera
{
    using CycleMath for CycleMath.CycleState;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Maximum cycles that can be paid in advance (1 year)
    uint256 private constant MAX_ADVANCE_CYCLES = 12;

    /// @dev Minimum monthly contribution (0.001 ETH or equivalent)
    uint256 private constant MIN_CONTRIBUTION = 1e15;

    /// @dev Maximum monthly contribution (1000 ETH or equivalent)
    uint256 private constant MAX_CONTRIBUTION = 1000 ether;

    /// @dev Maximum number of members (safety limit)
    uint256 private constant ABSOLUTE_MAX_MEMBERS = 200;

    /// @dev Maximum total months for natillera duration (5 years)
    uint256 private constant MAX_TOTAL_MONTHS = 60;

    /// @dev Minimum total months for natillera duration (3 months)
    uint256 private constant MIN_TOTAL_MONTHS = 3;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INatillera
    uint256 public override cycle;

    /// @inheritdoc INatillera
    uint256 public override cycleDueDate;

    /// @notice Cycle state managed by CycleMath library
    CycleMath.CycleState private _cycleState;

    /// @notice Natillera configuration
    NatilleraConfig private _config;

    /// @notice Member deposits tracking
    mapping(address => uint256) private _deposits;

    /// @notice Membership status tracking
    mapping(address => bool) private _isMember;

    /// @notice Array of all member addresses
    address[] private _members;

    /// @notice Total amount collected across all members
    uint256 private _totalCollected;

    /// @notice Total amount withdrawn by members
    uint256 private _totalWithdrawn;

    /// @notice Flag indicating if the natillera cycle is finalized
    bool public finalized;

    /// @notice Tracks members who have claimed their final share
    mapping(address => bool) public rewardsClaimed;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Ensures cycle is synchronized before execution
     */
    modifier syncCycle() {
        _syncCycle();
        _;
    }

    /**
     * @dev Restricts access to members only
     */
    modifier onlyMember() {
        if (!_isMember[msg.sender]) revert Natillera_NotMember();
        _;
    }

    /**
     * @dev Restricts access when contract is active (not paused)
     */
    modifier whenActive() {
        if (paused()) revert Natillera_ContractPaused();
        _;
    }

    /**
     * @dev Validates member address
     */
    modifier validMember(address member) {
        if (member == address(0)) revert Natillera_InvalidMember();
        if (member == address(this)) revert Natillera_InvalidMember();
        _;
    }

    /**
     * @dev Validates contribution amount
     */
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert Natillera_InvalidDeposit();
        if (amount > MAX_CONTRIBUTION * MAX_ADVANCE_CYCLES) {
            revert Natillera_InvalidDeposit();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc INatillera
     * @notice Initializes the Natillera contract
     * @dev Sets up configuration, ownership, and initial state
     */
    function initialize(
        uint256 startTimestamp,
        NatilleraConfig calldata natilleraConfig,
        IPlatform.GovernanceConfig calldata governanceConfig,
        IPlatform.ProjectConfig calldata projectConfig
    ) external override initializer notInitialized {
        // Validate start timestamp
        if (startTimestamp <= block.timestamp) revert Natillera_InvalidStart();
        if (startTimestamp > block.timestamp + 365 days) {
            revert Natillera_InvalidStart();
        }

        // Validate configuration
        _validateConfig(natilleraConfig);

        // Initialize Tracking with project information
        __Tracking_init(
            projectConfig.platform,
            projectConfig.projectId,
            projectConfig.creator
        );

        // Initialize other parent contracts
        __ReentrancyGuard_init();
        __Pausable_init();

        // Initialize base timestamp (one cycle before start)
        _cycleState.baseTimestamp =
            startTimestamp -
            CycleMath.SECONDS_PER_CYCLE;
        CycleMath.validateTimestamp(_cycleState.baseTimestamp);

        // Store configuration
        _config = natilleraConfig;

        // Initialize first cycle
        _syncCycle();

        emit NatilleraInitialized(
            projectConfig.projectId,
            projectConfig.creator,
            startTimestamp,
            natilleraConfig.monthlyContribution,
            natilleraConfig.maxMembers
        );
    }

    /*//////////////////////////////////////////////////////////////
                            CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc INatillera
     * @notice Tracks a member's contribution status
     */
    function trackContribution(
        address member
    )
        external
        override
        syncCycle
        validMember(member)
        returns (uint256 amountPaid, uint256 amountDue, uint256 missedCycles)
    {
        if (!_isMember[member]) revert Natillera_NotMember();
        return _calculateContribution(member);
    }

    /**
     * @inheritdoc INatillera
     * @notice Allows a member to deposit for a single cycle
     */
    function depositSingleCycle()
        external
        payable
        override
        onlyMember
        syncCycle
        nonReentrant
        whenActive
        validAmount(msg.value)
    {
        if (finalized) revert Natillera_ContractPaused(); // Block deposits if finalized
        _processDeposit(msg.sender, 1, msg.value);
    }

    /**
     * @inheritdoc INatillera
     * @notice Allows a member to deposit for multiple cycles
     */
    function depositMultipleCycles(
        uint256 cycles
    )
        external
        payable
        override
        onlyMember
        syncCycle
        nonReentrant
        whenActive
        validAmount(msg.value)
    {
        if (finalized) revert Natillera_ContractPaused(); // Block deposits if finalized
        if (cycles == 0 || cycles > MAX_ADVANCE_CYCLES) {
            revert Natillera_InvalidCycles();
        }
        _processDeposit(msg.sender, cycles, msg.value);
    }

    /**
     * @inheritdoc INatillera
     * @notice Adds a new member to the natillera
     */
    function addMember(
        address member
    ) external override onlyOwner whenActive validMember(member) {
        if (_isMember[member]) revert Natillera_AlreadyMember();
        if (_members.length >= _config.maxMembers) {
            revert Natillera_MaxMembersReached();
        }

        _isMember[member] = true;
        _members.push(member);

        // Register member with platform
        IPlatform(platform()).addUserToProject(projectId(), member);

        emit MemberAdded(member, block.timestamp);
    }

    /**
     * @inheritdoc INatillera
     */
    function batchAddMembers(
        address[] calldata newMembers
    ) external override onlyOwner whenActive {
        if (finalized) revert Natillera_ContractPaused(); // Cannot add members if finalized
        
        uint256 count = newMembers.length;
        if (count > 50) revert Natillera_InvalidConfig();

        address[] memory addedMembers = new address[](count);
        uint256 addedCount = 0;

        for (uint256 i = 0; i < count; ) {
            address member = newMembers[i];
            if (member != address(0) && member != address(this) && !_isMember[member]) {
                if (_members.length < _config.maxMembers) {
                    _isMember[member] = true;
                    _members.push(member);
                    IPlatform(platform()).addUserToProject(projectId(), member);
                    addedMembers[addedCount] = member;
                    addedCount++;
                }
            }
            unchecked { ++i; }
        }

        address[] memory finalAdded = new address[](addedCount);
        for(uint256 j=0; j<addedCount; j++){
            finalAdded[j] = addedMembers[j];
        }
        
        if (addedCount > 0) {
            emit MembersAddedBatch(finalAdded);
        }
    }

    /**
     * @inheritdoc INatillera
     */
    function finalize() external override onlyOwner {
        if (finalized) revert Natillera_ContractPaused(); // Already finalized
        
        finalized = true;
        uint256 totalBalance = address(this).balance;
        
        if (_config.token != address(0)) {
            totalBalance = IERC20(_config.token).balanceOf(address(this));
        }

        emit NatilleraFinalized(_totalCollected, totalBalance);
        _pause(); // Pause contract to strict safety
    }

    /**
     * @inheritdoc INatillera
     */
    function withdraw() external override nonReentrant {
        if (!finalized) revert Natillera_ContractNotPaused(); // Not finalized yet
        if (rewardsClaimed[msg.sender]) revert Natillera_InvalidDeposit(); // Already claimed (reuse error)
        if (!_isMember[msg.sender]) revert Natillera_NotMember();

        uint256 depositBalance = _deposits[msg.sender];
        if (depositBalance == 0) revert Natillera_InvalidDeposit();

        // Calculate Share: (UserDeposit * TotalAvailable) / TotalCollected
        // TotalAvailable includes original deposits + any external yields/transfers
        uint256 totalAvailable = address(this).balance; 
        if (_config.token != address(0)) {
            totalAvailable = IERC20(_config.token).balanceOf(address(this));
        }

        // Precision check: if totalCollected is 0 (should not happen if depositBalance > 0), avoid div by 0
        if (_totalCollected == 0) revert Natillera_InvalidConfig();

        uint256 amountToReceive = (depositBalance * totalAvailable) / _totalCollected;

        rewardsClaimed[msg.sender] = true;
        _totalWithdrawn += amountToReceive;

        if (_config.token == address(0)) {
            (bool success, ) = payable(msg.sender).call{value: amountToReceive}("");
            if (!success) revert Natillera_InvalidDeposit();
        } else {
            IERC20(_config.token).safeTransfer(msg.sender, amountToReceive);
        }

        emit FundsWithdrawn(msg.sender, amountToReceive);
    }

    /*//////////////////////////////////////////////////////////////
                            EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc INatillera
     * @notice Pauses the natillera, stopping deposits and member additions
     */
    function pause() external override onlyOwner {
        _pause();
    }

    /**
     * @inheritdoc INatillera
     * @notice Unpauses the natillera, resuming normal operations
     */
    function unpause() external override onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc INatillera
     * @notice Returns array of all member addresses
     */
    function members() external view override returns (address[] memory) {
        return _members;
    }

    /**
     * @inheritdoc INatillera
     * @notice Returns the current configuration
     */
    function config() external view override returns (NatilleraConfig memory) {
        return _config;
    }

    /**
     * @inheritdoc INatillera
     * @notice Returns deposit balance for a specific member
     */
    function getDepositBalance(
        address member
    ) external view override returns (uint256) {
        return _deposits[member];
    }

    /**
     * @inheritdoc INatillera
     * @notice Checks if an address is a member
     */
    function isMember(address account) external view override returns (bool) {
        return _isMember[account];
    }

    /**
     * @inheritdoc INatillera
     * @notice Returns total number of members
     */
    function memberCount() external view override returns (uint256) {
        return _members.length;
    }

    /**
     * @notice Returns cycle information
     * @return currentCycle Current cycle number
     * @return dueDate Current cycle due date
     * @return baseTimestamp Base timestamp for calculations
     */
    function getCycleInfo()
        external
        view
        returns (uint256 currentCycle, uint256 dueDate, uint256 baseTimestamp)
    {
        return (
            _cycleState.currentCycle,
            _cycleState.cycleDueDate,
            _cycleState.baseTimestamp
        );
    }

    /**
     * @notice Returns total collected amount
     * @return Total amount collected from all members
     */
    function totalCollected() external view returns (uint256) {
        return _totalCollected;
    }

    /**
     * @notice Returns total withdrawn amount
     * @return Total amount withdrawn by members
     */
    function totalWithdrawn() external view returns (uint256) {
        return _totalWithdrawn;
    }

    /**
     * @notice Returns available balance in contract
     * @return Current contract balance
     */
    function availableBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Calculates contribution status without state changes
     * @param member Member address
     * @return amountPaid Total amount paid
     * @return amountDue Amount currently due
     * @return missedCycles Number of cycles behind
     */
    function calculateContribution(
        address member
    )
        external
        view
        returns (uint256 amountPaid, uint256 amountDue, uint256 missedCycles)
    {
        if (!_isMember[member]) revert Natillera_NotMember();
        return _calculateContributionView(member);
    }

    /**
     * @notice Checks if natillera has ended based on total months
     * @return True if natillera has ended, false otherwise
     */
    function hasEnded() external view returns (bool) {
        return cycle >= _config.totalMonths;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Processes a deposit for specified number of cycles
     * @param member Address making the deposit
     * @param cycles Number of cycles being paid for
     * @param amount Deposit amount
     */
    function _processDeposit(
        address member,
        uint256 cycles,
        uint256 amount
    ) internal {
        uint256 monthlyContribution = _config.monthlyContribution;

        // Calculate expected amount with overflow check
        uint256 expectedAmount;
        unchecked {
            expectedAmount = monthlyContribution * cycles;
        }

        // Validate payment amount matches expected
        if (amount != expectedAmount) revert Natillera_InvalidDeposit();

        // Calculate current due amount
        (, uint256 amountDue, ) = _calculateContribution(member);

        // Validate payment does not exceed due amount
        if (amount > amountDue) revert Natillera_OverPayment();

        bool isUpToDate = amount == amountDue;

        // Update deposits with overflow check
        uint256 newDepositAmount = _deposits[member] + amount;
        require(
            newDepositAmount >= _deposits[member],
            "Natillera: deposit overflow"
        );

        // Update total collected
        uint256 newTotalCollected = _totalCollected + amount;
        require(
            newTotalCollected >= _totalCollected,
            "Natillera: total overflow"
        );

        _deposits[member] = newDepositAmount;
        _totalCollected = newTotalCollected;

        emit Deposit(member, amount, cycles, isUpToDate);
    }

    /**
     * @dev Synchronizes the current cycle based on timestamp
     */
    function _syncCycle() internal {
        uint256 oldCycle = cycle;

        // Use CycleMath library for safe synchronization
        _cycleState.syncCycle(block.timestamp);

        // Update public state variables
        cycle = _cycleState.currentCycle;
        cycleDueDate = _cycleState.cycleDueDate;

        // Emit event if cycle advanced
        if (cycle > oldCycle) {
            emit CycleAdvanced(oldCycle, cycle, cycleDueDate);
        }
    }

    /**
     * @dev Calculates contribution status for a member
     * @param member Address of the member
     * @return amountPaid Total amount paid
     * @return amountDue Amount currently due
     * @return missedCycles Number of cycles behind
     */
    function _calculateContribution(
        address member
    )
        internal
        view
        returns (uint256 amountPaid, uint256 amountDue, uint256 missedCycles)
    {
        return _calculateContributionView(member);
    }

    /**
     * @dev View version of contribution calculation
     */
    function _calculateContributionView(
        address member
    )
        private
        view
        returns (uint256 amountPaid, uint256 amountDue, uint256 missedCycles)
    {
        uint256 monthlyContribution = _config.monthlyContribution;

        amountPaid = _deposits[member];

        // Calculate total expected up to current cycle or total months
        uint256 cyclesToCalculate = cycle;
        if (cyclesToCalculate > _config.totalMonths) {
            cyclesToCalculate = _config.totalMonths;
        }

        uint256 totalExpected = monthlyContribution * cyclesToCalculate;

        if (amountPaid >= totalExpected) {
            return (amountPaid, 0, 0);
        }

        amountDue = totalExpected - amountPaid;
        missedCycles = amountDue / monthlyContribution;
    }

    /**
     * @dev Validates configuration parameters
     * @param config_ Configuration to validate
     */
    function _validateConfig(NatilleraConfig calldata config_) private pure {
        // Validate token address (can be zero for native)
        if (config_.token != address(0)) {
            // Additional ERC20 validation could be added here
        }

        // Validate contribution amount
        if (config_.monthlyContribution < MIN_CONTRIBUTION) {
            revert Natillera_InvalidConfig();
        }
        if (config_.monthlyContribution > MAX_CONTRIBUTION) {
            revert Natillera_InvalidConfig();
        }

        // Validate total months
        if (config_.totalMonths < MIN_TOTAL_MONTHS) {
            revert Natillera_InvalidConfig();
        }
        if (config_.totalMonths > MAX_TOTAL_MONTHS) {
            revert Natillera_InvalidConfig();
        }

        // Validate max members
        if (config_.maxMembers == 0) {
            revert Natillera_InvalidConfig();
        }
        if (config_.maxMembers > ABSOLUTE_MAX_MEMBERS) {
            revert Natillera_InvalidConfig();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                RECEIVE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows the contract to receive ETH
     * @dev Required for native token deposits
     */
    receive() external payable {}
}
