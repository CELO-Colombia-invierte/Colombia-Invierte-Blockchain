// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title INatilleraV2
 * @notice Interface for the rotating savings and credit association (ROSCA) module.
 */
interface INatilleraV2 {
    error ZeroAddress();
    error NotMember();
    error AlreadyPaid();
    error InvalidMonth();
    error NotMatured();
    error NotClosed();
    error CycleClosed();
    error AlreadyClaimed();
    error ZeroShares();
    error ZeroClaim();

    event Joined(address indexed user);
    event QuotaPaid(address indexed user, uint256 monthId);
    event Claimed(address indexed user, uint256 amount);

    /**
     * @notice Initializes the natillera with core parameters.
     * @param vault_ Address of the associated ProjectVault
     * @param depositToken_ Token used for quota payments
     * @param quota_ Fixed amount per monthly payment
     * @param duration_ Number of months the cycle lasts
     * @param startTimestamp_ Start time of the first month
     */
    function initialize(
        address vault_,
        address depositToken_,
        uint256 quota_,
        uint256 duration_,
        uint256 startTimestamp_
    ) external;

    /**
     * @notice Registers caller as a member.
     */
    function join() external;

    /**
     * @notice Pays quota for a specific month.
     * @param monthId Month number (1-indexed) to pay for
     */
    function payQuota(uint256 monthId) external;

    /**
     * @notice Claims proportional share of vault balance after maturity and vault closure.
     */
    function claimFinal() external;

    /**
     * @notice Checks if the cycle has matured.
     * @return True if cycle is matured
     */
    function isMatured() external view returns (bool);

    /**
     * @notice Returns total shares accumulated from all quota payments.
     * @return totalShares Total shares
     */
    function totalShares() external view returns (uint256);
}
