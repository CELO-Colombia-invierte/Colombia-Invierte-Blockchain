// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IProjectVault} from "../../../interfaces/v2/IProjectVault.sol";
import {INatilleraV2} from "../../../interfaces/v2/INatilleraV2.sol";
import {IFeeManager} from "../../../interfaces/v2/IFeeManager.sol";

/**
 * @title NatilleraV2
 * @notice Savings circle (natillera) module with quota payments, penalties, and final distribution.
 * @dev Clonable via EIP-1167. Members join, pay quotas, and claim final pool after maturity.
 * @author Key Lab Technical Team.
 */
contract NatilleraV2 is
    Initializable,
    ReentrancyGuardUpgradeable,
    INatilleraV2
{
    using SafeERC20 for IERC20;

    bytes32 internal constant NATILLERA_V2 = keccak256("NATILLERA_V2");
    uint256 internal constant BPS = 10000;

    IProjectVault public vault;
    IFeeManager public feeManager;
    IERC20 public depositToken;

    uint256 public quota;
    uint256 public duration;
    uint256 public startTimestamp;
    uint256 public paymentCycleDuration;
    uint16 public latePenaltyBps;

    uint256 public maxMembers;
    uint256 public memberCount;

    uint256 public override totalShares;
    uint256 public totalClaimed;
    uint256 public finalPool;
    bool public poolFinalized;

    mapping(address => bool) public isMember;
    mapping(address => mapping(uint256 => bool)) public paidMonth;
    mapping(address => uint256) public userShares;
    mapping(address => bool) public claimed;

    /*//////////////////////////////////////////////////////////////
                                INITIALIZE
    //////////////////////////////////////////////////////////////*/

    function initialize(
        address vault_,
        address feeManager_,
        address depositToken_,
        uint256 quota_,
        uint256 duration_,
        uint256 startTimestamp_,
        uint256 paymentCycleDuration_,
        uint16 latePenaltyBps_,
        uint256 maxMembers_
    ) external initializer {
        if (
            vault_ == address(0) ||
            feeManager_ == address(0) ||
            depositToken_ == address(0)
        ) revert ZeroAddress();
        if (startTimestamp_ < block.timestamp) revert InvalidStartTimestamp();
        if (duration_ == 0 || paymentCycleDuration_ == 0)
            revert InvalidConfig();
        if (maxMembers_ == 0) revert InvalidConfig();
        if (latePenaltyBps_ > BPS) revert InvalidConfig();

        __ReentrancyGuard_init();

        vault = IProjectVault(vault_);
        feeManager = IFeeManager(feeManager_);
        depositToken = IERC20(depositToken_);

        quota = quota_;
        duration = duration_;
        startTimestamp = startTimestamp_;
        paymentCycleDuration = paymentCycleDuration_;

        latePenaltyBps = latePenaltyBps_;
        maxMembers = maxMembers_;
    }

    /*//////////////////////////////////////////////////////////////
                                MEMBERSHIP
    //////////////////////////////////////////////////////////////*/

    function join() external {
        if (isMatured()) revert CycleClosed();
        if (isMember[msg.sender]) revert AlreadyMember();
        if (memberCount >= maxMembers) revert MaxMembersReached();

        isMember[msg.sender] = true;
        unchecked {
            memberCount++;
        }
        emit Joined(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                                PAYMENT
    //////////////////////////////////////////////////////////////*/

    function currentMonth() public view returns (uint256) {
        if (block.timestamp < startTimestamp) return 0;
        return ((block.timestamp - startTimestamp) / paymentCycleDuration) + 1;
    }

    /**
     * @notice Pays quota for a specific month, applies late penalty if applicable.
     * @dev Funds are deposited directly to vault.
     */
    function payQuota(uint256 monthId) external {
        if (isMatured()) revert CycleClosed();
        if (!isMember[msg.sender]) revert NotMember();
        if (monthId == 0 || monthId > duration) revert InvalidMonth();
        if (paidMonth[msg.sender][monthId]) revert AlreadyPaid();

        paidMonth[msg.sender][monthId] = true;

        uint256 monthNow = currentMonth();
        if (monthId > monthNow + 1) revert InvalidMonth();
        uint256 penalty = monthId < monthNow
            ? (quota * latePenaltyBps) / BPS
            : 0;

        uint256 totalPayment = quota + penalty;

        userShares[msg.sender] += quota;
        totalShares += quota;

        vault.depositFrom(msg.sender, address(depositToken), totalPayment);
        emit QuotaPaid(msg.sender, monthId);
    }

    /*//////////////////////////////////////////////////////////////
                                MATURITY
    //////////////////////////////////////////////////////////////*/

    function isMatured() public view returns (bool) {
        return
            block.timestamp >=
            startTimestamp + (duration * paymentCycleDuration);
    }

    /*//////////////////////////////////////////////////////////////
                                CLAIM
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims final share of the pool after vault closure.
     * @dev Calculates proportional share, deducts fees, and releases from vault.
     */
    function claimFinal() external nonReentrant {
        if (!isMatured()) revert NotMatured();
        if (vault.state() != IProjectVault.VaultState.Closed)
            revert NotClosed();
        if (claimed[msg.sender]) revert AlreadyClaimed();
        if (totalShares == 0) revert ZeroShares();

        uint256 shares = userShares[msg.sender];
        if (shares == 0) revert ZeroShares();

        if (!poolFinalized) {
            finalPool = depositToken.balanceOf(address(vault));
            poolFinalized = true;
        }

        uint256 rawAmount = (shares * finalPool) / totalShares;
        if (rawAmount == 0) revert ZeroClaim();

        uint256 remaining = finalPool - totalClaimed;
        if (rawAmount > remaining) rawAmount = remaining;

        (uint256 fee, uint256 net) = feeManager.calculateFee(
            NATILLERA_V2,
            rawAmount
        );

        claimed[msg.sender] = true;
        totalClaimed += rawAmount;

        vault.releaseOnClose(
            address(depositToken),
            feeManager.feeTreasury(),
            fee
        );
        vault.releaseOnClose(address(depositToken), msg.sender, net);

        emit Claimed(msg.sender, net);
    }
}
