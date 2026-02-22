// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IProjectVault} from "../../../interfaces/v2/IProjectVault.sol";
import {INatilleraV2} from "../../../interfaces/v2/INatilleraV2.sol";
import {IFeeManager} from "../../../interfaces/v2/IFeeManager.sol";

/**
 * @title NatilleraV2
 * @notice Rotating savings and credit association (ROSCA) module with fee support.
 * @dev Members pay fixed quotas monthly and claim proportional share at maturity.
 */
contract NatilleraV2 is
    Initializable,
    ReentrancyGuardUpgradeable,
    INatilleraV2
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 internal constant NATILLERA_V2 = keccak256("NATILLERA_V2");

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    IProjectVault public vault;
    IFeeManager public feeManager;
    IERC20 public depositToken;

    uint256 public quota;
    uint256 public duration;
    uint256 public startTimestamp;

    uint256 public override totalShares;
    uint256 public totalClaimed;
    uint256 public finalPool;
    bool public poolFinalized;

    mapping(address => bool) public isMember;
    mapping(address => mapping(uint256 => bool)) public paidMonth;
    mapping(address => uint256) public userShares;
    mapping(address => bool) public claimed;

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the natillera with core parameters.
     * @param vault_ Address of the associated ProjectVault
     * @param feeManager_ Address of the fee manager contract
     * @param depositToken_ Token used for quota payments
     * @param quota_ Fixed amount per monthly payment
     * @param duration_ Number of months the cycle lasts
     * @param startTimestamp_ Start time of the first month
     */
    function initialize(
        address vault_,
        address feeManager_,
        address depositToken_,
        uint256 quota_,
        uint256 duration_,
        uint256 startTimestamp_
    ) external initializer {
        if (
            vault_ == address(0) ||
            feeManager_ == address(0) ||
            depositToken_ == address(0)
        ) revert ZeroAddress();

        __ReentrancyGuard_init();

        vault = IProjectVault(vault_);
        feeManager = IFeeManager(feeManager_);
        depositToken = IERC20(depositToken_);

        quota = quota_;
        duration = duration_;
        startTimestamp = startTimestamp_;
    }

    /*//////////////////////////////////////////////////////////////
                            MEMBERSHIP
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers caller as a member.
     */
    function join() external {
        if (isMatured()) revert CycleClosed();
        isMember[msg.sender] = true;
        emit Joined(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            PAY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pays quota for a specific month.
     * @param monthId Month number (1-indexed) to pay for
     */
    function payQuota(uint256 monthId) external {
        if (isMatured()) revert CycleClosed();
        if (!isMember[msg.sender]) revert NotMember();
        if (monthId == 0 || monthId > duration) revert InvalidMonth();
        if (paidMonth[msg.sender][monthId]) revert AlreadyPaid();

        paidMonth[msg.sender][monthId] = true;

        userShares[msg.sender] += quota;
        totalShares += quota;

        vault.depositFrom(msg.sender, address(depositToken), quota);

        emit QuotaPaid(msg.sender, monthId);
    }

    /*//////////////////////////////////////////////////////////////
                            MATURITY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if the cycle has matured.
     * @return True if current time >= start + duration months
     */
    function isMatured() public view returns (bool) {
        return block.timestamp >= startTimestamp + (duration * 30 days);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims proportional share of vault balance after maturity and vault closure.
     * @dev Applies fees via FeeManager before distribution.
     */
    function claimFinal() external nonReentrant {
        if (!isMatured()) revert NotMatured();
        if (vault.state() != IProjectVault.VaultState.Closed)
            revert NotClosed();
        if (claimed[msg.sender]) revert AlreadyClaimed();

        uint256 shares = userShares[msg.sender];
        if (shares == 0) revert ZeroShares();

        // Cache final pool on first claim to handle potential balance changes
        if (!poolFinalized) {
            finalPool = depositToken.balanceOf(address(vault));
            poolFinalized = true;
        }

        uint256 rawAmount = (shares * finalPool) / totalShares;
        if (rawAmount == 0) revert ZeroClaim();

        // Dust control: ensure we don't claim more than remaining
        uint256 remaining = finalPool - totalClaimed;
        if (rawAmount > remaining) {
            rawAmount = remaining;
        }

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
