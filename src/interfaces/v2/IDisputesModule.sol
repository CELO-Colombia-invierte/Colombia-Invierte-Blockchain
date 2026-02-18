// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IDisputesModule
 * @notice Interface for the disputes module that handles dispute lifecycle and vault freezing.
 */
interface IDisputesModule {
    enum DisputeStatus {
        None,
        Open,
        ResolvedAccepted,
        ResolvedRejected
    }

    struct Dispute {
        address opener;
        string reason;
        uint256 openedAt;
        DisputeStatus status;
    }

    event DisputeOpened(uint256 indexed id, address indexed opener);
    event DisputeResolved(uint256 indexed id, bool accepted);

    /**
     * @notice Initializes the disputes module with vault and governance addresses.
     * @param vault_ Address of the associated ProjectVault
     * @param governance_ Address authorized to resolve disputes
     */
    function initialize(address vault_, address governance_) external;

    /**
     * @notice Opens a new dispute and immediately pauses the vault.
     * @param reason Human-readable justification for the dispute
     * @return id Unique identifier for the created dispute
     */
    function openDispute(string calldata reason) external returns (uint256);

    /**
     * @notice Resolves an open dispute, setting its final status.
     * @param id ID of the dispute to resolve
     * @param accepted True if dispute is accepted, false if rejected
     */
    function resolveDispute(uint256 id, bool accepted) external;

    /**
     * @notice Returns the total number of disputes created.
     * @return disputeCount Total disputes
     */
    function disputeCount() external view returns (uint256);

    /**
     * @notice Returns dispute details by ID.
     * @param id Dispute ID to query
     * @return opener Address that opened the dispute
     * @return reason Dispute reason string
     * @return openedAt Timestamp when dispute was opened
     * @return status Current dispute status
     */
    function disputes(
        uint256 id
    )
        external
        view
        returns (
            address opener,
            string memory reason,
            uint256 openedAt,
            DisputeStatus status
        );
}
