// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IRevenueModuleV2
 * @notice Interface for the revenue module that manages token sales and reward distribution.
 */
interface IRevenueModuleV2 {
    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/
    enum State {
        Pending,
        Active,
        Successful,
        Failed,
        DistributionEnded
    }
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error SaleClosed();
    error FundingTargetReached();
    error ZeroAmount();
    error DistributionEnded();
    error NothingToClaim();
    error Unauthorized();
    error InvalidState();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Invested(
        address indexed investor,
        uint256 amount,
        uint256 tokensMinted
    );
    event RevenueDeposited(uint256 amount);
    event Claimed(address indexed user, uint256 amount);
    event SaleFinalized();
    event Swept(address treasury, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the revenue module with sale and distribution parameters.
     * @param token_ Address of the project token
     * @param vault_ Address receiving invested funds
     * @param settlementToken_ Token used for investment and rewards
     * @param fundingTarget_ Target amount to raise
     * @param tokenPrice_ Price per token in settlementToken units
     * @param saleStart_ Timestamp when sale begins
     * @param saleEnd_ Timestamp when sale ends
     * @param distributionEnd_ Timestamp when revenue distribution ends
     * @param expectedApy_ Expected annual percentage yield
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
    ) external;

    /**
     * @notice Invests settlement tokens to receive project tokens.
     * @param amount Amount of settlement tokens to invest
     */
    function invest(uint256 amount) external;

    /**
     * @notice Deposits revenue for distribution to token holders.
     * @param amount Amount of revenue to deposit
     */
    function depositRevenue(uint256 amount) external;

    /**
     * @notice Claims accumulated rewards for the caller.
     */
    function claim() external;

    /**
     * @notice Hook called by ProjectToken before transfers to update reward debt.
     * @param from Sender address
     * @param to Recipient address
     * @param amount Transfer amount
     */
    function beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) external;

    /**
     * @notice Returns the current state of the revenue module.
     * @return state Current State enum value
     */
    function state() external view returns (State);
}
