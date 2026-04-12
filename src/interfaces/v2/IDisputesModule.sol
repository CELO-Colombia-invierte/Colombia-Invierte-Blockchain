// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IDisputesModule
 * @notice Interface for the disputes module that handles dispute lifecycle and vault freezing.
 * @author Key Lab Technical Team.
 */
interface IDisputesModule {
  /*//////////////////////////////////////////////////////////////
                              ENUMS
  //////////////////////////////////////////////////////////////*/

  enum DisputeStatus {
    None,
    Open,
    Frozen,
    ResolvedAccepted,
    ResolvedRejected
  }

  /*//////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  struct Dispute {
    address opener;
    string reason;
    uint256 openedAt;
    DisputeStatus status;
  }

  /*//////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  error ZeroAddress();
  error NotActiveVault();
  error InvalidDispute();
  error AlreadyResolved();
  error Unauthorized();
  error AlreadyPaused();
  error AlreadyProcessed();

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  event DisputesInitialized(address indexed vault, address indexed governance);
  event DisputeOpened(uint256 indexed id, address indexed opener);
  event DisputeResolved(uint256 indexed id, bool accepted);

  function initialize(address vault_, address governance_) external;

  function openDispute(string calldata reason) external returns (uint256);

  function resolveDispute(uint256 id, bool accepted) external;

  function disputeCount() external view returns (uint256);

  function disputes(uint256 id)
    external
    view
    returns (address opener, string memory reason, uint256 openedAt, DisputeStatus status);

  function markFrozen(uint256 id) external;
}
