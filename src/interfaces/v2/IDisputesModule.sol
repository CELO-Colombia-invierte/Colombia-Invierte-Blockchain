// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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

    function initialize(address vault_, address governance_) external;

    function openDispute(string calldata reason) external returns (uint256);

    function resolveDispute(uint256 id, bool accepted) external;

    function disputeCount() external view returns (uint256);

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
