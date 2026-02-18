// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IMilestonesModule
 * @notice Interface for the milestones module that manages project milestone lifecycle.
 */
interface IMilestonesModule {
    enum MilestoneStatus {
        None,
        Proposed,
        Approved,
        Executed
    }

    struct Milestone {
        string description;
        address token;
        address recipient;
        uint256 amount;
        MilestoneStatus status;
    }

    event MilestonesInitialized(
        address indexed vault,
        address indexed governance
    );
    event MilestoneProposed(uint256 indexed id);
    event MilestoneApproved(uint256 indexed id);
    event MilestoneExecuted(uint256 indexed id);

    /**
     * @notice Initializes the milestones module with vault and governance addresses.
     * @param vault_ Address of the associated ProjectVault
     * @param governance_ Address authorized to manage milestones
     */
    function initialize(address vault_, address governance_) external;

    /**
     * @notice Creates a new milestone proposal.
     * @param description Human-readable description of the milestone
     * @param token Address of the token to be released
     * @param recipient Address that will receive funds upon execution
     * @param amount Amount of tokens to release
     * @return id Unique identifier for the created milestone
     */
    function proposeMilestone(
        string calldata description,
        address token,
        address recipient,
        uint256 amount
    ) external returns (uint256);

    /**
     * @notice Approves a proposed milestone, making it eligible for execution.
     * @param id ID of the milestone to approve
     */
    function approveMilestone(uint256 id) external;

    /**
     * @notice Executes an approved milestone, releasing funds from the vault.
     * @param id ID of the milestone to execute
     */
    function executeMilestone(uint256 id) external;

    /**
     * @notice Returns the total number of milestones created.
     * @return milestoneCount Total milestones
     */
    function milestoneCount() external view returns (uint256);

    /**
     * @notice Returns milestone details by ID.
     * @param id Milestone ID to query
     * @return description Milestone description
     * @return token Token address for release
     * @return recipient Recipient address
     * @return amount Amount to release
     * @return status Current milestone status
     */
    function milestones(
        uint256 id
    )
        external
        view
        returns (
            string memory description,
            address token,
            address recipient,
            uint256 amount,
            MilestoneStatus status
        );
}
