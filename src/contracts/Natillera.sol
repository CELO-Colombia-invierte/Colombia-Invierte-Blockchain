// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Tracking} from "contracts/Tracking.sol";
import {CycleMath} from "contracts/libraries/CycleMath.sol";
import {INatillera} from "interfaces/INatillera.sol";
import {IPlatform} from "interfaces/IPlatform.sol";

/**
 * @title Natillera
 * @author K-Labs
 * @notice Savings pool with proportional distribution at maturity
 * @dev Implements the "Pool de Ahorros" model: monthly contributions accumulate,
 *      distributed proportionally at the end based on individual contributions
 * @custom:features Monthly cycles, overpayment credits, external yield deposits,
 *                  emergency withdrawals, auto-finalization
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

    /// @notice Maximum cycles that can be paid in advance (1 year)
    uint256 private constant MAX_ADVANCE_CYCLES = 12;

    /// @notice Minimum monthly contribution (0.001 ETH or equivalent)
    uint256 private constant MIN_CONTRIBUTION = 1e15;

    /// @notice Maximum monthly contribution (1000 ETH or equivalent)
    uint256 private constant MAX_CONTRIBUTION = 1000 ether;

    /// @notice Absolute maximum number of members (safety limit)
    uint256 private constant MAX_MEMBERS = 200;

    /// @notice Maximum pool duration in months (5 years)
    uint256 private constant MAX_TOTAL_MONTHS = 60;

    /// @notice Minimum pool duration in months (3 months)
    uint256 private constant MIN_TOTAL_MONTHS = 3;

    /// @notice Delay before emergency withdrawal becomes available (90 days)
    uint256 private constant EMERGENCY_DELAY = 90 days;

    /// @notice Credit expiry period (1 year)
    uint256 private constant CREDIT_EXPIRY_PERIOD = 365 days;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INatillera
    uint256 public override cycle;

    /// @inheritdoc INatillera
    uint256 public override cycleDueDate;

    /// @inheritdoc INatillera
    bool public override finalized;

    /// @notice Internal cycle state managed by CycleMath library
    CycleMath.CycleState private _cycleState;

    /// @notice Pool configuration parameters
    NatilleraConfig private _config;

    /// @inheritdoc INatillera
    mapping(address => uint256) public override depositBalance;

    /// @notice Membership status tracking
    mapping(address => bool) private _isMember;

    /// @inheritdoc INatillera
    mapping(address => bool) public override rewardsClaimed;

    /// @inheritdoc INatillera
    mapping(address => uint256) public override credits;

    /// @notice Credit expiry timestamps
    mapping(address => uint256) public override creditExpiry;

    /// @notice List of all member addresses
    address[] private _members;

    /// @inheritdoc INatillera
    uint256 public override totalCollected;

    /// @inheritdoc INatillera
    uint256 public override totalWithdrawn;

    /// @inheritdoc INatillera
    uint256 public override totalYieldDeposited;

    /// @inheritdoc INatillera
    uint256 public override totalYieldDistributed;

    /// @notice Yield claimed per member (for internal tracking)
    mapping(address => uint256) private _yieldClaimed;

    /// @notice Last activity timestamp per member (for emergency withdrawal)
    mapping(address => uint256) private _lastActivity;

    /// @notice Last owner action timestamp (for emergency withdrawal validation)
    uint256 private _lastOwnerAction;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Ensures cycle is synchronized with current timestamp before execution
     * @dev Automatically advances cycle and triggers auto-finalization if needed
     */
    modifier syncCycle() {
        _syncCycle();
        _;
    }

    /**
     * @dev Restricts function access to pool members only
     */
    modifier onlyMember() {
        if (!_isMember[msg.sender]) revert NotMember();
        _;
    }

    /**
     * @dev Restricts function access when contract is not paused
     */
    modifier whenActive() {
        if (paused()) revert ContractPaused();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc INatillera
     * @dev Validates configuration parameters and sets up initial state
     * @dev The governanceConfig parameter is reserved for future use
     */
    function initialize(
        uint256 startTimestamp,
        NatilleraConfig calldata natilleraConfig,
        IPlatform.GovernanceConfig calldata,
        IPlatform.ProjectConfig calldata projectConfig
    ) external override initializer {
        // Validate start timestamp is in reasonable future
        if (startTimestamp <= block.timestamp) revert InvalidStart();
        if (startTimestamp > block.timestamp + 365 days) revert InvalidStart();

        // Validate configuration parameters
        _validateConfig(natilleraConfig);

        // Initialize parent contracts
        __Tracking_init(
            projectConfig.platform,
            projectConfig.projectId,
            projectConfig.creator
        );
        __ReentrancyGuard_init();
        __Pausable_init();

        // Set up cycle state (cycle 0 starts at startTimestamp)
        _cycleState.baseTimestamp = startTimestamp;
        _config = natilleraConfig;

        // Initialize first cycle (due in 30 days)
        _cycleState.currentCycle = 0;
        _cycleState.cycleDueDate = startTimestamp + CycleMath.SECONDS_PER_CYCLE;
        cycle = _cycleState.currentCycle;
        cycleDueDate = _cycleState.cycleDueDate;

        // Initialize owner activity tracker
        _lastOwnerAction = block.timestamp;

        emit NatilleraInitialized(
            projectConfig.projectId,
            projectConfig.creator,
            startTimestamp,
            natilleraConfig.monthlyContribution,
            natilleraConfig.maxMembers
        );
    }

    /*//////////////////////////////////////////////////////////////
                            CORE CONTRIBUTION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc INatillera
     * @dev Automatically syncs cycle, validates amount, processes deposit
     */
    function depositSingleCycle()
        external
        payable
        override
        onlyMember
        syncCycle
        nonReentrant
        whenActive
    {
        if (finalized) revert AlreadyFinalized();

        uint256 monthlyContribution = _config.monthlyContribution;
        if (msg.value != monthlyContribution) revert InvalidDeposit();

        // Validate single cycle payment doesn't exceed due amount
        (, uint256 amountDue, ) = _calculateContribution(msg.sender);
        if (msg.value > amountDue) revert OverPayment();

        _processDeposit(msg.sender, 1, msg.value, 0);
        _updateActivity(msg.sender);
    }

    /**
     * @inheritdoc INatillera
     * @dev Validates cycles parameter is within allowed range
     * @dev Allows overpayment for advance cycles
     */
    function depositMultipleCycles(
        uint256 cycles
    ) external payable override onlyMember syncCycle nonReentrant whenActive {
        if (finalized) revert AlreadyFinalized();
        if (cycles == 0 || cycles > MAX_ADVANCE_CYCLES) revert InvalidCycles();

        uint256 monthlyContribution = _config.monthlyContribution;
        uint256 expectedAmount = monthlyContribution * cycles;

        if (msg.value != expectedAmount) revert InvalidDeposit();

        // For multiple cycles, validate against total pool capacity
        uint256 totalCapacity = monthlyContribution * _config.totalMonths;
        uint256 newTotal = depositBalance[msg.sender] + msg.value;
        if (newTotal > totalCapacity) revert OverPayment();

        _processDeposit(msg.sender, cycles, msg.value, 0);
        _updateActivity(msg.sender);
    }

    /**
     * @inheritdoc INatillera
     * @dev Excess payment above exact amount is stored as credit for future use
     */
    function depositWithOverpayment(
        uint256 cycles
    ) external payable override onlyMember syncCycle nonReentrant whenActive {
        if (finalized) revert AlreadyFinalized();
        if (cycles == 0 || cycles > MAX_ADVANCE_CYCLES) revert InvalidCycles();

        uint256 monthlyContribution = _config.monthlyContribution;
        uint256 exactAmount = monthlyContribution * cycles;

        if (msg.value < exactAmount) revert InvalidDeposit();

        // Validate total doesn't exceed pool capacity
        uint256 totalCapacity = monthlyContribution * _config.totalMonths;
        uint256 newTotal = depositBalance[msg.sender] + exactAmount;
        if (newTotal > totalCapacity) revert OverPayment();

        _processDeposit(msg.sender, cycles, exactAmount, 0);

        uint256 overpayment = msg.value - exactAmount;
        if (overpayment > 0) {
            credits[msg.sender] += overpayment;
            creditExpiry[msg.sender] = block.timestamp + CREDIT_EXPIRY_PERIOD;
            emit OverpaymentDeposited(msg.sender, overpayment);
        }

        _updateActivity(msg.sender);
    }

    /**
     * @inheritdoc INatillera
     * @dev Uses credit balance to cover one monthly contribution
     * @dev Validates credit hasn't expired
     */
    function useCreditForCycle()
        external
        override
        onlyMember
        syncCycle
        nonReentrant
        whenActive
    {
        if (finalized) revert AlreadyFinalized();

        // Check credit expiry
        if (creditExpiry[msg.sender] < block.timestamp) {
            credits[msg.sender] = 0;
            revert CreditExpired();
        }

        uint256 monthlyContribution = _config.monthlyContribution;
        if (credits[msg.sender] < monthlyContribution)
            revert InsufficientCredit();

        credits[msg.sender] -= monthlyContribution;
        _processDeposit(
            msg.sender,
            1,
            monthlyContribution,
            monthlyContribution
        );

        emit CreditUsed(msg.sender, monthlyContribution);
        _updateActivity(msg.sender);
    }

    /**
     * @inheritdoc INatillera
     * @dev Only owner can deposit yield from external sources
     * @dev Yield is added to pool for proportional distribution at maturity
     */
    function depositYield() external payable override nonReentrant {
        _requireOwner();
        if (finalized) revert AlreadyFinalized();
        if (msg.value == 0) revert NoYield();
        if (_config.token != address(0)) revert InvalidYieldToken();

        totalYieldDeposited += msg.value;
        _lastOwnerAction = block.timestamp;

        emit YieldDeposited(msg.sender, msg.value);
    }

    /**
     * @inheritdoc INatillera
     * @dev Transfers ERC20 tokens from owner to pool as yield
     */
    function depositYieldERC20(uint256 amount) external override nonReentrant {
        _requireOwner();
        if (finalized) revert AlreadyFinalized();
        if (amount == 0) revert NoYield();
        if (_config.token == address(0)) revert InvalidYieldToken();

        IERC20(_config.token).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        totalYieldDeposited += amount;
        _lastOwnerAction = block.timestamp;

        emit YieldDepositedERC20(msg.sender, _config.token, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMINISTRATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc INatillera
     * @dev Registers new member with the platform and tracks membership
     */
    function addMember(address member) external override whenActive {
        _requireOwner();
        if (member == address(0) || member == address(this))
            revert InvalidMember();
        if (_isMember[member]) revert AlreadyMember();
        if (_members.length >= _config.maxMembers) revert MaxMembersReached();

        _isMember[member] = true;
        _members.push(member);
        _lastActivity[member] = block.timestamp;
        _lastOwnerAction = block.timestamp;

        IPlatform(platform()).addUserToProject(projectId(), member);
        emit MemberAdded(member);
    }

    /**
     * @inheritdoc INatillera
     * @dev More gas-efficient than adding members individually
     * @dev Skips invalid addresses and existing members
     */
    function batchAddMembers(
        address[] calldata newMembers
    ) external override whenActive {
        _requireOwner();
        if (finalized) revert AlreadyFinalized();

        uint256 count = newMembers.length;
        address[] memory addedMembers = new address[](count);
        uint256 addedCount = 0;

        for (uint256 i = 0; i < count; ) {
            address member = newMembers[i];
            if (
                member != address(0) &&
                member != address(this) &&
                !_isMember[member]
            ) {
                if (_members.length < _config.maxMembers) {
                    _isMember[member] = true;
                    _members.push(member);
                    _lastActivity[member] = block.timestamp;
                    IPlatform(platform()).addUserToProject(projectId(), member);
                    addedMembers[addedCount] = member;
                    addedCount++;
                }
            }
            unchecked {
                ++i;
            }
        }

        if (addedCount > 0) {
            _lastOwnerAction = block.timestamp;
            address[] memory finalAdded = new address[](addedCount);
            for (uint256 j = 0; j < addedCount; j++) {
                finalAdded[j] = addedMembers[j];
            }
            emit MembersAddedBatch(finalAdded);
        }
    }

    /**
     * @inheritdoc INatillera
     * @dev Also triggers auto-pause for added security
     * @dev Auto-finalization also occurs when totalMonths is reached
     */
    function finalize() external override {
        _requireOwner();
        if (finalized) revert AlreadyFinalized();

        finalized = true;
        _lastOwnerAction = block.timestamp;
        uint256 totalAvailable = _getTotalAvailable();

        emit PoolFinalized(totalCollected, totalAvailable);
        _pause();
    }

    /**
     * @inheritdoc INatillera
     */
    function pause() external override {
        _requireOwner();
        _pause();
        _lastOwnerAction = block.timestamp;
    }

    /**
     * @inheritdoc INatillera
     */
    function unpause() external override {
        _requireOwner();
        _unpause();
        _lastOwnerAction = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                            MEMBER WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc INatillera
     * @dev Calculates capital share as exact deposit amount
     * @dev Calculates yield share as: (memberDeposit / totalCollected) * availableYield
     * @dev Can only be called once per member after finalization
     */
    function withdraw() external override nonReentrant {
        if (!finalized) revert NotFinalized();
        if (rewardsClaimed[msg.sender]) revert AlreadyClaimed();
        if (!_isMember[msg.sender]) revert NotMember();

        uint256 memberDeposit = depositBalance[msg.sender];
        if (memberDeposit == 0) revert InvalidDeposit();

        (
            uint256 capitalShare,
            uint256 yieldShare
        ) = _calculateProportionalShare(msg.sender);
        uint256 totalToReceive = capitalShare + yieldShare;
        if (totalToReceive == 0) revert InvalidDeposit();

        rewardsClaimed[msg.sender] = true;
        totalWithdrawn += capitalShare;
        totalYieldDistributed += yieldShare;
        _yieldClaimed[msg.sender] = yieldShare;

        if (_config.token == address(0)) {
            (bool success, ) = payable(msg.sender).call{value: totalToReceive}(
                ""
            );
            if (!success) revert TransferFailed();
        } else {
            IERC20(_config.token).safeTransfer(msg.sender, totalToReceive);
        }

        emit FundsWithdrawn(msg.sender, capitalShare, yieldShare);
    }

    /**
     * @inheritdoc INatillera
     * @dev Available after 90 days of owner inactivity
     * @dev WARNING: Reduces totalCollected, affecting proportional calculations for remaining members
     * @dev Withdraws only capital contributions (no yield)
     * @dev Intended as last resort when owner cannot finalize pool
     */
    function emergencyWithdraw() external override onlyMember nonReentrant {
        if (finalized) revert AlreadyFinalized();

        // Check emergency conditions
        if (block.timestamp <= cycleDueDate + EMERGENCY_DELAY)
            revert ContractNotPaused();
        if (_hasOwnerBeenActive()) revert OwnerActive();

        uint256 memberDeposit = depositBalance[msg.sender];
        if (memberDeposit == 0) revert InvalidDeposit();

        depositBalance[msg.sender] = 0;
        totalCollected -= memberDeposit;

        if (_config.token == address(0)) {
            (bool success, ) = payable(msg.sender).call{value: memberDeposit}(
                ""
            );
            if (!success) revert TransferFailed();
        } else {
            IERC20(_config.token).safeTransfer(msg.sender, memberDeposit);
        }

        emit EmergencyWithdrawal(msg.sender, memberDeposit);
    }

    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc INatillera
     */
    function members() external view override returns (address[] memory) {
        return _members;
    }

    /**
     * @inheritdoc INatillera
     */
    function config() external view override returns (NatilleraConfig memory) {
        return _config;
    }

    /**
     * @inheritdoc INatillera
     */
    function isMember(address account) external view override returns (bool) {
        return _isMember[account];
    }

    /**
     * @inheritdoc INatillera
     */
    function hasEnded() external view override returns (bool) {
        return cycle >= _config.totalMonths;
    }

    /**
     * @inheritdoc INatillera
     * @dev Capital share is always exact deposit amount
     * @dev Yield share is proportional based on contribution
     */
    function calculateShare(
        address member
    )
        external
        view
        override
        returns (uint256 capitalShare, uint256 yieldShare, uint256 totalShare)
    {
        if (!_isMember[member] || depositBalance[member] == 0) {
            return (0, 0, 0);
        }

        uint256 memberDeposit = depositBalance[member];

        // Capital is always exactly what was deposited
        capitalShare = memberDeposit;

        // Calculate yield share
        if (!finalized) {
            // Theoretical yield if pool ended now
            if (totalYieldDeposited > 0 && totalCollected > 0) {
                yieldShare =
                    (memberDeposit * totalYieldDeposited) /
                    totalCollected;
            }
        } else {
            // Actual yield after finalization
            uint256 totalYieldAvailable = totalYieldDeposited -
                totalYieldDistributed;
            if (totalYieldAvailable > 0 && totalCollected > 0) {
                yieldShare =
                    (memberDeposit * totalYieldAvailable) /
                    totalCollected;
            }
        }

        totalShare = capitalShare + yieldShare;

        // Ensure we don't exceed available balance
        uint256 totalAvailable = _getTotalAvailable();
        if (totalShare > totalAvailable) {
            // Adjust yield only, capital is fixed
            uint256 maxYield = totalAvailable > capitalShare
                ? totalAvailable - capitalShare
                : 0;
            yieldShare = yieldShare > maxYield ? maxYield : yieldShare;
            totalShare = capitalShare + yieldShare;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Processes a deposit, validating amount and updating balances
     * @param member Address making the deposit
     * @param cycles Number of cycles being paid for
     * @param amount Total amount being deposited
     * @param fromCredit Amount being paid from credit balance (0 for cash payments)
     */
    function _processDeposit(
        address member,
        uint256 cycles,
        uint256 amount,
        uint256 fromCredit
    ) internal {
        bool isUpToDate = _isMemberUpToDate(member, amount);

        uint256 depositIncrease = amount - fromCredit;
        if (depositIncrease > 0) {
            depositBalance[member] += depositIncrease;
            totalCollected += depositIncrease;
        }

        emit Deposit(member, amount, cycles, isUpToDate);
    }

    /**
     * @dev Synchronizes the current cycle with block timestamp
     * @dev Automatically finalizes pool when totalMonths is reached
     */
    function _syncCycle() internal {
        uint256 oldCycle = cycle;

        _cycleState.syncCycle(block.timestamp);
        cycle = _cycleState.currentCycle;
        cycleDueDate = _cycleState.cycleDueDate;

        // Auto-finalization when pool reaches its duration
        if (cycle >= _config.totalMonths && !finalized) {
            finalized = true;
            uint256 totalAvailable = _getTotalAvailable();
            emit PoolFinalized(totalCollected, totalAvailable);
            _pause();
        }

        if (cycle > oldCycle) {
            emit CycleAdvanced(oldCycle, cycle, cycleDueDate);
        }
    }

    /**
     * @dev Calculates proportional share for a member
     * @param member Address to calculate share for
     * @return capitalShare Member's exact capital deposit
     * @return yieldShare Member's proportional share of yield
     */
    function _calculateProportionalShare(
        address member
    ) internal view returns (uint256 capitalShare, uint256 yieldShare) {
        uint256 memberDeposit = depositBalance[member];

        // Capital share is exactly what was deposited
        capitalShare = memberDeposit;

        // Calculate yield share proportionally
        uint256 totalYieldAvailable = totalYieldDeposited -
            totalYieldDistributed;
        if (totalYieldAvailable > 0 && totalCollected > 0) {
            yieldShare = (memberDeposit * totalYieldAvailable) / totalCollected;
        }

        // Ensure we don't exceed available balance
        uint256 totalShare = capitalShare + yieldShare;
        uint256 totalAvailable = _getTotalAvailable();

        if (totalShare > totalAvailable) {
            // Adjust yield only, capital is fixed
            uint256 maxYield = totalAvailable > capitalShare
                ? totalAvailable - capitalShare
                : 0;
            yieldShare = yieldShare > maxYield ? maxYield : yieldShare;
        }
    }

    /**
     * @dev Calculates current contribution status for a member
     * @param member Address to check
     * @return amountPaid Total amount paid by member
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
        uint256 monthlyContribution = _config.monthlyContribution;
        amountPaid = depositBalance[member];

        uint256 cyclesToCalculate = cycle > _config.totalMonths
            ? _config.totalMonths
            : cycle;
        uint256 totalExpected = monthlyContribution * cyclesToCalculate;

        if (amountPaid >= totalExpected) {
            return (amountPaid, 0, 0);
        }

        amountDue = totalExpected - amountPaid;
        missedCycles = amountDue / monthlyContribution;
    }

    /**
     * @dev Determines if a member will be up-to-date after a deposit
     * @param member Address to check
     * @param newAmount Amount being deposited
     * @return True if member will be up-to-date after deposit
     */
    function _isMemberUpToDate(
        address member,
        uint256 newAmount
    ) private view returns (bool) {
        (, uint256 amountDueBefore, ) = _calculateContribution(member);
        return newAmount >= amountDueBefore;
    }

    /**
     * @dev Gets total available balance in the pool
     * @return Total balance (native or ERC20 depending on configuration)
     */
    function _getTotalAvailable() internal view returns (uint256) {
        return
            _config.token == address(0)
                ? address(this).balance
                : IERC20(_config.token).balanceOf(address(this));
    }

    /**
     * @dev Updates last activity timestamp for a member
     * @param member Address to update
     */
    function _updateActivity(address member) internal {
        _lastActivity[member] = block.timestamp;
    }

    /**
     * @dev Checks if owner has been active recently
     * @return True if owner has taken action within half the emergency delay
     */
    function _hasOwnerBeenActive() internal view returns (bool) {
        return block.timestamp <= _lastOwnerAction + (EMERGENCY_DELAY / 2);
    }

    /**
     * @dev Validates configuration parameters
     * @param config_ Configuration to validate
     */
    function _validateConfig(NatilleraConfig calldata config_) private pure {
        if (config_.monthlyContribution < MIN_CONTRIBUTION)
            revert InvalidConfig();
        if (config_.monthlyContribution > MAX_CONTRIBUTION)
            revert InvalidConfig();
        if (config_.totalMonths < MIN_TOTAL_MONTHS) revert InvalidConfig();
        if (config_.totalMonths > MAX_TOTAL_MONTHS) revert InvalidConfig();
        if (config_.maxMembers == 0 || config_.maxMembers > MAX_MEMBERS)
            revert InvalidConfig();
    }

    /*//////////////////////////////////////////////////////////////
                                RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows contract to receive native currency
     * @dev Only accepts ETH when pool is not finalized
     * @dev Rejects accidental transfers to finalized pools
     */
    receive() external payable {
        if (finalized) {
            revert AlreadyFinalized();
        }
        emit EtherReceived(msg.sender, msg.value);
    }
}
