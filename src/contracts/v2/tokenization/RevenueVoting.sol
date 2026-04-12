// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IProjectTokenV2} from '../../../interfaces/v2/IProjectTokenV2.sol';
import {IVotingStrategy} from '../../../interfaces/v2/IVotingStrategy.sol';

/**
 * @title RevenueVoting
 * @notice Voting strategy for tokenization projects.
 * @dev Voting power is proportional to token balance at snapshot block.
 * @author Key Lab Technical Team.
 */
contract RevenueVoting is IVotingStrategy {
  IProjectTokenV2 public token;

  constructor(IProjectTokenV2 _token) {
    if (address(_token) == address(0)) revert ZeroAddress();
    token = _token;
  }

  function getVotingPower(address user, uint256 snapshotBlock) external view returns (uint256) {
    return token.getPastVotes(user, snapshotBlock);
  }
}
