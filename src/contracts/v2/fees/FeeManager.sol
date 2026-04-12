// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import {IFeeManager} from '../../../interfaces/v2/IFeeManager.sol';

/**
 * @title FeeManager
 * @notice Manages fee configuration and calculation for various modules.
 * @dev Fees are expressed in basis points (bps) with a 50% maximum cap.
 * @author Key Lab Technical Team.
 */
contract FeeManager is Initializable, OwnableUpgradeable, IFeeManager {
  /*//////////////////////////////////////////////////////////////
                              CONSTANTS
  //////////////////////////////////////////////////////////////*/

  uint16 public constant MAX_BPS = 5000; // 50% cap
  uint16 internal constant BPS_DENOMINATOR = 10_000;

  bytes32 public constant NATILLERA_V2 = keccak256('NATILLERA_V2');
  bytes32 public constant TOKENIZATION_V2 = keccak256('TOKENIZATION_V2');

  /*//////////////////////////////////////////////////////////////
                              STORAGE
  //////////////////////////////////////////////////////////////*/

  address public override feeTreasury;
  mapping(bytes32 => uint16) public feeConfig;

  /*//////////////////////////////////////////////////////////////
                              INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Initializes the FeeManager with a treasury address and default fees.
   * @param treasury_ Address that will receive collected fees
   */
  function initialize(address treasury_) external initializer {
    if (treasury_ == address(0)) revert ZeroAddress();

    __Ownable_init(msg.sender);
    feeTreasury = treasury_;
    feeConfig[NATILLERA_V2] = 300; // 3%
    feeConfig[TOKENIZATION_V2] = 3000; // 30%
  }

  /*//////////////////////////////////////////////////////////////
                              ADMIN
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Sets the fee for a specific module type.
   * @dev Reverts if fee exceeds MAX_BPS.
   */
  function setFee(bytes32 feeType, uint16 bps) external onlyOwner {
    if (bps > MAX_BPS) revert FeeTooHigh();
    feeConfig[feeType] = bps;
    emit FeeUpdated(feeType, bps);
  }

  /**
   * @notice Updates the fee treasury address.
   */
  function setTreasury(address newTreasury) external onlyOwner {
    if (newTreasury == address(0)) revert ZeroAddress();
    feeTreasury = newTreasury;
    emit TreasuryUpdated(newTreasury);
  }

  /*//////////////////////////////////////////////////////////////
                              VIEW
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Calculates fee and net amount for a given module and raw amount.
   * @return feeAmount Amount to be sent to treasury
   * @return netAmount Amount to be sent to user
   */
  function calculateFee(
    bytes32 feeType,
    uint256 amount
  ) external view override returns (uint256 feeAmount, uint256 netAmount) {
    uint16 bps = feeConfig[feeType];
    if (bps == 0) revert FeeNotConfigured();
    if (feeTreasury == address(0)) revert ZeroAddress();

    feeAmount = (amount * bps) / BPS_DENOMINATOR;
    netAmount = amount - feeAmount;
  }
}
