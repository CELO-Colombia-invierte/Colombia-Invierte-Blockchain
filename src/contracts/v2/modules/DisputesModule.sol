// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDisputesModule} from '../../../interfaces/v2/IDisputesModule.sol';
import {IProjectVault} from '../../../interfaces/v2/IProjectVault.sol';
import {IStakeholder} from '../../../interfaces/v2/IStakeholder.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';

/**
 * @title DisputesModule
 * @notice Handles dispute lifecycle and emergency freezing of the vault.
 * @dev Clonable via EIP-1167. Opening a dispute requires stakeholder status.
 * @author Key Lab Technical Team.
 */
contract DisputesModule is Initializable, ReentrancyGuardUpgradeable, IDisputesModule {
  /*//////////////////////////////////////////////////////////////
                              STORAGE
  //////////////////////////////////////////////////////////////*/

  IProjectVault public vault;
  address public governance;
  uint256 public disputeCount;
  mapping(uint256 => Dispute) public disputes;

  /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor() {
    _disableInitializers();
  }

  /*//////////////////////////////////////////////////////////////
                              INITIALIZER
  //////////////////////////////////////////////////////////////*/

  function initialize(address vault_, address governance_) external initializer {
    if (vault_ == address(0) || governance_ == address(0)) {
      revert ZeroAddress();
    }

    __ReentrancyGuard_init();

    vault = IProjectVault(vault_);
    governance = governance_;

    emit DisputesInitialized(vault_, governance_);
  }

  /*//////////////////////////////////////////////////////////////
                              CORE LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Opens a new dispute and immediately pauses the vault.
   * @dev Only stakeholders can open disputes. Vault must be Active and not paused.
   */
  function openDispute(string calldata reason) external nonReentrant returns (uint256 id) {
    address project = vault.project();
    if (!IStakeholder(project).isStakeholder(msg.sender)) {
      revert Unauthorized();
    }
    if (vault.state() != IProjectVault.VaultState.Active) {
      revert NotActiveVault();
    }
    if (vault.paused()) revert AlreadyPaused();

    id = ++disputeCount;
    disputes[id] = Dispute({opener: msg.sender, reason: reason, openedAt: block.timestamp, status: DisputeStatus.Open});

    emit DisputeOpened(id, msg.sender);
  }

  function markFrozen(uint256 disputeId) external {
    if (msg.sender != governance) revert Unauthorized();

    Dispute storage d = disputes[disputeId];
    if (d.status != DisputeStatus.Open) revert InvalidDispute();

    d.status = DisputeStatus.Frozen;
  }

  /**
   * @notice Resolves an open dispute, setting its final status.
   * @dev Vault remains paused—governance must unpause separately.
   */
  function resolveDispute(uint256 id, bool accepted) external nonReentrant {
    if (msg.sender != governance) revert Unauthorized();

    Dispute storage d = disputes[id];
    if (d.status == DisputeStatus.None) revert InvalidDispute();
    if (d.status != DisputeStatus.Open) revert AlreadyResolved();

    d.status = accepted ? DisputeStatus.ResolvedAccepted : DisputeStatus.ResolvedRejected;
    emit DisputeResolved(id, accepted);
  }
}
