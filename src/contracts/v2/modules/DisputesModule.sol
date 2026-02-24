// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IProjectVault} from "../../../interfaces/v2/IProjectVault.sol";

/**
 * @title DisputesModule
 * @notice Handles dispute lifecycle and emergency freezing of the vault.
 * @dev Clonable via EIP-1167. Opening a dispute automatically pauses the vault.
 * @author Key Lab Technical Team.
 */
contract DisputesModule is Initializable, ReentrancyGuardUpgradeable {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();
    error NotActiveVault();
    error InvalidDispute();
    error AlreadyResolved();
    error Unauthorized();

    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/

    enum DisputeStatus {
        None,
        Open,
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
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    IProjectVault public vault;
    address public governance;
    uint256 public disputeCount;
    mapping(uint256 => Dispute) public disputes;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event DisputesInitialized(
        address indexed vault,
        address indexed governance
    );
    event DisputeOpened(uint256 indexed id, address indexed opener);
    event DisputeResolved(uint256 indexed id, bool accepted);

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the disputes module with vault and governance addresses.
     */
    function initialize(
        address vault_,
        address governance_
    ) external initializer {
        if (vault_ == address(0) || governance_ == address(0))
            revert ZeroAddress();

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
     * @dev Vault must be Active. Pauses vault to freeze activity during review.
     */
    function openDispute(
        string calldata reason
    ) external nonReentrant returns (uint256 id) {
        if (msg.sender != governance) revert Unauthorized();
        if (vault.state() != IProjectVault.VaultState.Active)
            revert NotActiveVault();

        id = ++disputeCount;
        disputes[id] = Dispute({
            opener: msg.sender,
            reason: reason,
            openedAt: block.timestamp,
            status: DisputeStatus.Open
        });

        vault.pause();
        emit DisputeOpened(id, msg.sender);
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

        d.status = accepted
            ? DisputeStatus.ResolvedAccepted
            : DisputeStatus.ResolvedRejected;
        emit DisputeResolved(id, accepted);
    }
}
