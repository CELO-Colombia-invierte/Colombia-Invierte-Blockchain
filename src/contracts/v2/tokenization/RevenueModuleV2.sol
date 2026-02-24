// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IRevenueModuleV2} from "../../../interfaces/v2/IRevenueModuleV2.sol";
import {IProjectVault} from "../../../interfaces/v2/IProjectVault.sol";
import {IProjectTokenV2} from "../../../interfaces/v2/IProjectTokenV2.sol";
import {IFeeManager} from "../../../interfaces/v2/IFeeManager.sol";

/**
 * @title RevenueModuleV2
 * @notice Manages investment, refunds, revenue distribution and fee handling for tokenization projects.
 * @dev Clonable via EIP-1167. Handles funding lifecycle and reward accrual.
 * @author Key Lab Technical Team.
 */
contract RevenueModuleV2 is
    Initializable,
    ReentrancyGuardUpgradeable,
    IRevenueModuleV2
{
    using SafeERC20 for IERC20;

    uint256 internal constant PRECISION = 1e12;
    bytes32 internal constant MODULE_ID = keccak256("TOKENIZATION_V2");

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    IProjectTokenV2 public token;
    IProjectVault public vault;
    IFeeManager public feeManager;
    IERC20 public settlementToken;

    address public governance;
    address public projectCreator;

    uint128 public fundingTarget;
    uint128 public minimumCap;
    uint128 public tokenPrice;

    uint64 public saleStart;
    uint64 public saleEnd;
    uint64 public distributionEnd;

    uint16 public expectedApy;

    uint128 public totalRaised;
    uint128 public accRewardPerShare;

    bool public saleFinalized;

    mapping(address => uint256) public investments;
    mapping(address => uint256) public rewardDebt;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZE
    //////////////////////////////////////////////////////////////*/

    function initialize(InitParams calldata p) external initializer {
        if (
            p.token == address(0) ||
            p.vault == address(0) ||
            p.settlementToken == address(0) ||
            p.governance == address(0) ||
            p.projectCreator == address(0) ||
            p.feeManager == address(0)
        ) revert Unauthorized();

        __ReentrancyGuard_init();

        token = IProjectTokenV2(p.token);
        vault = IProjectVault(p.vault);
        settlementToken = IERC20(p.settlementToken);
        feeManager = IFeeManager(p.feeManager);

        fundingTarget = uint128(p.fundingTarget);
        minimumCap = uint128(p.minimumCap);
        tokenPrice = uint128(p.tokenPrice);

        saleStart = uint64(p.saleStart);
        saleEnd = uint64(p.saleEnd);
        distributionEnd = uint64(p.distributionEnd);

        expectedApy = p.expectedApy;

        governance = p.governance;
        projectCreator = p.projectCreator;
    }

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    function state() public view override returns (State) {
        uint256 ts = block.timestamp;
        if (ts < saleStart) return State.Pending;
        if (ts <= saleEnd) {
            if (totalRaised >= fundingTarget) return State.Successful;
            return State.Active;
        }
        if (totalRaised >= minimumCap) return State.Successful;
        return State.Failed;
    }

    /*//////////////////////////////////////////////////////////////
                                INVEST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Invests settlement tokens in exchange for project tokens.
     * @dev Transfers funds directly to vault. Updates reward debt.
     */
    function invest(uint256 amount) external nonReentrant {
        if (state() != State.Active) revert SaleClosed();
        if (amount == 0) revert ZeroAmount();

        uint128 raised = totalRaised;
        if (raised + amount > fundingTarget) revert FundingTargetReached();
        if (amount > type(uint128).max - raised) revert InvalidState();

        uint256 tokensToMint = amount / tokenPrice;

        // casting to uint128 is safe because we check the upper bound above
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amount128 = uint128(amount);

        totalRaised = raised + amount128;
        investments[msg.sender] += amount;

        settlementToken.safeTransferFrom(msg.sender, address(vault), amount);
        token.mint(msg.sender, tokensToMint);

        rewardDebt[msg.sender] =
            (IERC20(address(token)).balanceOf(msg.sender) * accRewardPerShare) /
            PRECISION;
        emit Invested(msg.sender, amount, tokensToMint);
    }

    /*//////////////////////////////////////////////////////////////
                            FINALIZE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Finalizes successful sale, deducts fees and distributes to creator.
     * @dev Only callable by governance when sale is successful.
     */
    function finalizeSale() external nonReentrant {
        if (msg.sender != governance) revert Unauthorized();
        if (state() != State.Successful || saleFinalized) revert InvalidState();

        saleFinalized = true;

        // Activar vault antes de liberar fondos
        vault.activate();

        uint256 balance = totalRaised;

        (uint256 fee, uint256 net) = feeManager.calculateFee(
            MODULE_ID,
            balance
        );

        address treasury = feeManager.feeTreasury();
        if (treasury == address(0)) revert Unauthorized();

        vault.release(address(settlementToken), treasury, fee);
        vault.release(address(settlementToken), projectCreator, net);

        emit SaleFinalized();
    }

    /*//////////////////////////////////////////////////////////////
                                REFUND
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims refund when sale fails. Burns tokens and returns funds.
     */
    function refund() external nonReentrant {
        if (state() != State.Failed) revert InvalidState();

        uint256 invested = investments[msg.sender];
        if (invested == 0) revert NothingToClaim();

        investments[msg.sender] = 0;

        // Cerrar vault si aún no está cerrado
        if (vault.state() != IProjectVault.VaultState.Closed) {
            vault.close();
        }

        uint256 bal = IERC20(address(token)).balanceOf(msg.sender);
        if (bal > 0) {
            token.burn(msg.sender, bal);
        }

        vault.releaseOnClose(address(settlementToken), msg.sender, invested);

        emit Refunded(msg.sender, invested);
    }

    /*//////////////////////////////////////////////////////////////
                        REWARD DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits revenue for distribution to token holders.
     * @dev Updates accRewardPerShare based on total supply.
     */
    function depositRevenue(uint256 amount) external nonReentrant {
        if (state() != State.Successful) revert InvalidState();
        if (amount == 0) revert ZeroAmount();

        settlementToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 supply = IERC20(address(token)).totalSupply();
        if (supply != 0) {
            uint256 rewardIncrement = (amount * PRECISION) / supply;
            if (rewardIncrement > type(uint128).max) revert InvalidState();

            // casting to uint128 is safe because rewardIncrement is bounded above
            // forge-lint: disable-next-line(unsafe-typecast)
            accRewardPerShare += uint128(rewardIncrement);
        }

        emit RevenueDeposited(amount);
    }

    /**
     * @notice Claims accumulated rewards for msg.sender.
     */
    function claim() external nonReentrant {
        if (block.timestamp > distributionEnd) revert DistributionEnded();

        uint256 balance = IERC20(address(token)).balanceOf(msg.sender);
        uint256 accumulated = (balance * accRewardPerShare) / PRECISION;
        uint256 debt = rewardDebt[msg.sender];

        if (accumulated <= debt) revert NothingToClaim();

        uint256 claimable = accumulated - debt;
        rewardDebt[msg.sender] = accumulated;

        settlementToken.safeTransfer(msg.sender, claimable);
        emit Claimed(msg.sender, claimable);
    }

    function pending(address user) external view override returns (uint256) {
        uint256 balance = IERC20(address(token)).balanceOf(user);
        uint256 accumulated = (balance * accRewardPerShare) / PRECISION;
        uint256 debt = rewardDebt[user];
        return accumulated <= debt ? 0 : accumulated - debt;
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN HOOK
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Updates reward debt on transfers to maintain accrual integrity.
     */
    function beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) external override {
        if (msg.sender != address(token)) revert Unauthorized();

        uint256 acc = accRewardPerShare;
        if (from != address(0)) {
            rewardDebt[from] =
                (IERC20(address(token)).balanceOf(from) * acc) /
                PRECISION;
        }
        if (to != address(0)) {
            rewardDebt[to] =
                (IERC20(address(token)).balanceOf(to) * acc) /
                PRECISION;
        }
    }
}
