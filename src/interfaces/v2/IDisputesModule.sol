// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IDisputesModule
 * @notice Interface for the Disputes Module of the Colombia Invierte platform.
 *         This module allows users to open disputes related to project vaults and for authorized parties to resolve them.
 */

interface IDisputesModule {
    /// @notice Enum representing the status of a dispute.
    enum DisputeStatus {
        None,
        Open,
        ResolvedAccepted,
        ResolvedRejected
    }
    /// @notice Struct representing a dispute opened by a user.
    struct Dispute {
        address opener;
        string reason;
        uint256 openedAt;
        DisputeStatus status;
    }
    /// @notice Emitted when a new dispute is opened.
    event DisputeOpened(uint256 indexed id, address indexed opener);
    /// @notice Emitted when a dispute is resolved.
    event DisputeResolved(uint256 indexed id, bool accepted);

    /**
     * @notice Opens a new dispute with the provided reason. The caller must be a user of an active project vault.
     * @param reason The reason for the dispute.
     */
    function openDispute(string calldata reason) external returns (uint256);

    /**
     * @notice Resolves an existing dispute by its ID. The caller must have the appropriate permissions to resolve disputes.
     * @param id The ID of the dispute to resolve.
     * @param accepted A boolean indicating whether the dispute is accepted (true) or rejected (false).
     */
    function resolveDispute(uint256 id, bool accepted) external;
}
