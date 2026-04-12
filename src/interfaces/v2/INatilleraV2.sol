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
  error VaultPaused();
  error InvalidVaultState();
  error AlreadyFinalized();
  error ZeroPool();
  error NotFinalized();
  error FullyClaimed();
  error Unauthorized();
  error InvalidState();
  error ZeroAmount();

  event Joined(address indexed user);
  event QuotaPaid(address indexed user, uint256 monthId);
  event Claimed(address indexed user, uint256 amount);
  event PoolFinalized(uint256 finalPool);
  event FeesSettled(uint256 reserved, uint256 totalFee);
  event YieldReturned(address indexed returner, address indexed source, uint256 amount);

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

  function returnYield(uint256 amount, address source) external;

  function totalYieldReturned() external view returns (uint256);

  function claimFinal() external;

  function isMatured() external view returns (bool);

  function totalShares() external view returns (uint256);

  function isMember(address user) external view returns (bool);

  function memberCount() external view returns (uint256);

  function settleFees() external;

  function finalizePool() external;

  function isStakeholder(address user) external view returns (bool);
}
