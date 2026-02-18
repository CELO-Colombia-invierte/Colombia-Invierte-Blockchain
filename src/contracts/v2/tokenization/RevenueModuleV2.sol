// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IRevenueModuleV2} from "../../../interfaces/v2/IRevenueModuleV2.sol";
import {IProjectTokenV2} from "../../../interfaces/v2/IProjectTokenV2.sol";

/**
 * @title RevenueModuleV2
 * @notice Manages token sale and revenue distribution to token holders.
 * @dev Handles investment, revenue deposits, and proportional reward claims.
 * @dev Historical rewards DO NOT transfer with tokens. Users must claim() before transferring.
 */
contract RevenueModuleV2 is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    IRevenueModuleV2
{
    using SafeERC20 for IERC20;

    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    uint256 public constant PRECISION = 1e24;

    IERC20 public token;
    IProjectTokenV2 public projectToken;
    IERC20 public settlementToken;
    address public vault;

    uint256 public fundingTarget;
    uint256 public tokenPrice;
    uint256 public totalRaised;
    uint256 public accRewardPerShare;

    uint256 public saleStart;
    uint256 public saleEnd;
    uint256 public distributionEnd;

    uint16 public expectedApy;

    mapping(address => uint256) public rewardDebt;

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the revenue module with sale and distribution parameters.
     * @param token_ Address of the project token (must implement IProjectTokenV2)
     * @param vault_ Address receiving invested funds
     * @param settlementToken_ Token used for investment and rewards
     * @param fundingTarget_ Target amount to raise
     * @param tokenPrice_ Price per token in settlementToken units
     * @param saleStart_ Timestamp when sale begins
     * @param saleEnd_ Timestamp when sale ends
     * @param distributionEnd_ Timestamp when revenue distribution ends
     * @param expectedApy_ Expected annual percentage yield (basis points)
     * @param governance_ Address with governance role
     */
    function initialize(
        address token_,
        address vault_,
        address settlementToken_,
        uint256 fundingTarget_,
        uint256 tokenPrice_,
        uint256 saleStart_,
        uint256 saleEnd_,
        uint256 distributionEnd_,
        uint16 expectedApy_,
        address governance_
    ) external initializer {
        if (saleStart_ >= saleEnd_) revert InvalidState();
        if (distributionEnd_ <= saleEnd_) revert InvalidState();
        if (tokenPrice_ == 0) revert ZeroAmount();
        if (fundingTarget_ == 0) revert ZeroAmount();

        token = IERC20(token_);
        projectToken = IProjectTokenV2(token_);
        vault = vault_;
        settlementToken = IERC20(settlementToken_);

        fundingTarget = fundingTarget_;
        tokenPrice = tokenPrice_;
        saleStart = saleStart_;
        saleEnd = saleEnd_;
        distributionEnd = distributionEnd_;
        expectedApy = expectedApy_;

        _grantRole(GOVERNANCE_ROLE, governance_);

        __ReentrancyGuard_init();
    }

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyDuringSale() {
        _onlyDuringSale();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            INVESTMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Invests settlement tokens to receive project tokens.
     * @param amount Amount of settlement tokens to invest
     */
    function invest(uint256 amount) external nonReentrant onlyDuringSale {
        state();
        if (amount == 0) revert ZeroAmount();
        if (totalRaised + amount > fundingTarget) revert FundingTargetReached();

        settlementToken.safeTransferFrom(msg.sender, vault, amount);

        uint256 tokensToMint = amount / tokenPrice;
        if (tokensToMint == 0) revert ZeroAmount();

        unchecked {
            totalRaised += amount;
        }

        uint256 debtIncrease = (tokensToMint * accRewardPerShare) / PRECISION;

        rewardDebt[msg.sender] += debtIncrease;

        projectToken.mint(msg.sender, tokensToMint);

        emit Invested(msg.sender, amount, tokensToMint);
    }

    /*//////////////////////////////////////////////////////////////
                            REVENUE DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits revenue for distribution to token holders.
     * @dev Callable only by governance during distribution period.
     */
    function depositRevenue(
        uint256 amount
    ) external nonReentrant onlyRole(GOVERNANCE_ROLE) {
        state();
        if (block.timestamp > distributionEnd) revert DistributionEnded();
        if (amount == 0) revert ZeroAmount();

        settlementToken.safeTransferFrom(vault, address(this), amount);

        uint256 supply = token.totalSupply();
        if (supply == 0) return;

        accRewardPerShare += (amount * PRECISION) / supply;

        emit RevenueDeposited(amount);
    }

    /**
     * @notice Claims accumulated rewards for the caller.
     */
    function claim() external nonReentrant {
        state();
        uint256 balance = token.balanceOf(msg.sender);
        uint256 accumulated = (balance * accRewardPerShare) / PRECISION;
        uint256 debt = rewardDebt[msg.sender];

        if (accumulated <= debt) revert NothingToClaim();

        uint256 claimable = accumulated - debt;

        rewardDebt[msg.sender] = accumulated;

        settlementToken.safeTransfer(msg.sender, claimable);

        emit Claimed(msg.sender, claimable);
    }

    /*//////////////////////////////////////////////////////////////
                            TOKEN HOOK
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Called by ProjectToken before any transfer to move reward debt proportionally.
     */
    function beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) external override {
        if (msg.sender != address(projectToken)) revert Unauthorized();
        if (amount == 0) return;
        if (from == address(0)) return; // mint

        uint256 debtToMove = (amount * accRewardPerShare) / PRECISION;

        uint256 fromDebt = rewardDebt[from];

        // burn
        if (to == address(0)) {
            rewardDebt[from] = fromDebt > debtToMove
                ? fromDebt - debtToMove
                : 0;
            return;
        }

        // transfer
        rewardDebt[from] = fromDebt > debtToMove ? fromDebt - debtToMove : 0;

        rewardDebt[to] += debtToMove;
    }

    /*//////////////////////////////////////////////////////////////
                                VIEW
    //////////////////////////////////////////////////////////////*/

    function state() public view returns (State) {
        if (block.timestamp > distributionEnd) return State.DistributionEnded;

        if (block.timestamp < saleStart) return State.Pending;

        if (block.timestamp <= saleEnd) return State.Active;

        return totalRaised >= fundingTarget ? State.Successful : State.Failed;
    }

    /**
     * @notice Calculates pending rewards for a user.
     * @param user Address to check
     * @return Pending reward amount
     */
    function pending(address user) external view returns (uint256) {
        uint256 balance = token.balanceOf(user);

        uint256 accumulated = (balance * accRewardPerShare) / PRECISION;

        uint256 debt = rewardDebt[user];

        if (accumulated < debt) {
            return 0;
        }

        return accumulated - debt;
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _onlyDuringSale() internal view {
        if (block.timestamp < saleStart || block.timestamp > saleEnd)
            revert SaleClosed();
    }
}
