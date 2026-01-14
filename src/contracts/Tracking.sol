// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ITracking} from 'interfaces/ITracking.sol';

contract Tracking is ITracking {
  /// @inheritdoc ITracking
  address public PLATFORM;

  /// @inheritdoc ITracking
  uint256 public uuid;
}