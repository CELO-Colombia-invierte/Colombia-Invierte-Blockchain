// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IProjectVault} from "../../../interfaces/v2/IProjectVault.sol";

/**
 * @title DisputesModule
 * @notice Implementation of the Disputes Module for the Colombia Invierte platform.
 *         This module allows users to open disputes related to project vaults and for authorized parties to resolve them.
 */
contract DisputesModule {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    //// @notice Error thrown when trying to open a dispute on a vault that is not active.
    error NotActiveVault();
    /// @notice Error thrown when trying to resolve a dispute that does not exist or is not open.
    error InvalidDispute();
    /// @notice Error thrown when trying to resolve a dispute that has already been resolved.
    error AlreadyResolved();
    /// @notice Error thrown when a caller without the necessary permissions tries to resolve a dispute.
    error Unauthorized();

    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/
    /// @notice Enum representing the status of a dispute.
    enum DisputeStatus {
        None,
        Open,
        ResolvedAccepted,
        ResolvedRejected
    }

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Struct representing a dispute opened by a user.
    struct Dispute {
        address opener;
        string reason;
        uint256 openedAt;
        DisputeStatus status;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @notice Reference to the associated project vault.
    IProjectVault public immutable vault;
    /// @notice Counter for dispute IDs.
    uint256 public disputeCount;
    /// @notice Mapping from dispute ID to Dispute details.
    mapping(uint256 => Dispute) public disputes;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Emitted when a new dispute is opened.
    event DisputeOpened(uint256 indexed id, address indexed opener);
    /// @notice Emitted when a dispute is resolved.
    event DisputeResolved(uint256 indexed id, bool accepted);

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Constructor for the DisputesModule. Initializes the module with a reference to the associated project vault.
     * @param vault_ The address of the associated project vault.
     */
    constructor(address vault_) {
        vault = IProjectVault(vault_);
    }

    /*//////////////////////////////////////////////////////////////
                            CORE LOGIC
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Opens a new dispute with the provided reason. The caller must be a user of an active project vault.
     * @param reason The reason for the dispute.
     */
    function openDispute(string calldata reason) external returns (uint256 id) {
        if (vault.state() != IProjectVault.VaultState.Active)
            revert NotActiveVault();

        id = ++disputeCount;

        disputes[id] = Dispute({
            opener: msg.sender,
            reason: reason,
            openedAt: block.timestamp,
            status: DisputeStatus.Open
        });

        // Pausamos el vault automáticamente
        vault.pause();

        emit DisputeOpened(id, msg.sender);
    }

    /**
     * @notice Resolves an existing dispute by its ID. The caller must have the appropriate permissions to resolve disputes.
     * @param id The ID of the dispute to resolve.
     * @param accepted A boolean indicating whether the dispute is accepted (true) or rejected (false).
     */
    function resolveDispute(uint256 id, bool accepted) external {
        Dispute storage d = disputes[id];

        if (d.status == DisputeStatus.None) revert InvalidDispute();
        if (d.status != DisputeStatus.Open) revert AlreadyResolved();

        if (!vault.canResolveDispute(msg.sender)) revert Unauthorized();

        if (accepted) {
            d.status = DisputeStatus.ResolvedAccepted;
            vault.close();
        } else {
            d.status = DisputeStatus.ResolvedRejected;
            vault.unpause();
        }

        emit DisputeResolved(id, accepted);
    }
}
