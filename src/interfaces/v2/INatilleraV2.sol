// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title INatilleraV2
 * @notice Interface for the natillera (savings circle) module.
 * @author Key Lab Technical Team.
 */
interface INatilleraV2 {
    error ZeroAddress();
    error InvalidConfig();
    error InvalidStartTimestamp();
    error NotMember();
    error AlreadyMember();
    error AlreadyPaid();
    error InvalidMonth();
    error NotMatured();
    error NotClosed();
    error CycleClosed();
    error AlreadyClaimed();
    error ZeroShares();
    error ZeroClaim();
    error MaxMembersReached();

    event Joined(address indexed user);
    event QuotaPaid(address indexed user, uint256 monthId);
    event Claimed(address indexed user, uint256 amount);

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
    ) external;

    function join() external;

    function payQuota(uint256 monthId) external;

    function claimFinal() external;

    function isMatured() external view returns (bool);

    function totalShares() external view returns (uint256);

    function isMember(address user) external view returns (bool);

    function memberCount() external view returns (uint256);
}
