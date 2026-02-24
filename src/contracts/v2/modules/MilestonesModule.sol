// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IProjectVault} from "../../../interfaces/v2/IProjectVault.sol";
import {IMilestonesModule} from "../../../interfaces/v2/IMilestonesModule.sol";

/**
 * @title MilestonesModule
 * @notice Manages the lifecycle of project milestones from proposal to execution.
 * @dev Clonable via EIP-1167. Only governance can propose, approve, and execute milestones.
 * @author Key Lab Technical Team.
 */
contract MilestonesModule is
    Initializable,
    ReentrancyGuardUpgradeable,
    IMilestonesModule
{
    error ZeroAddress();
    error ZeroAmount();
    error Unauthorized();
    error InvalidMilestone();
    error InvalidState();

    IProjectVault public vault;
    address public governance;
    uint256 public override milestoneCount;
    mapping(uint256 => Milestone) public override milestones;

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the milestones module with vault and governance addresses.
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

        emit MilestonesInitialized(vault_, governance_);
    }

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyGovernance() {
        _onlyGovernance();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            MILESTONE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new milestone proposal.
     */
    function proposeMilestone(
        string calldata description,
        address token,
        address recipient,
        uint256 amount
    ) external override onlyGovernance returns (uint256 id) {
        if (token == address(0) || recipient == address(0))
            revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        id = ++milestoneCount;
        milestones[id] = Milestone({
            description: description,
            token: token,
            recipient: recipient,
            amount: amount,
            status: MilestoneStatus.Proposed
        });
        emit MilestoneProposed(id);
    }

    /**
     * @notice Approves a proposed milestone, making it eligible for execution.
     */
    function approveMilestone(uint256 id) external override onlyGovernance {
        Milestone storage m = milestones[id];
        if (m.status != MilestoneStatus.Proposed) revert InvalidState();
        m.status = MilestoneStatus.Approved;
        emit MilestoneApproved(id);
    }

    /**
     * @notice Executes an approved milestone, releasing funds from the vault.
     * @dev Reverts if vault release fails (e.g., insufficient balance, wrong state).
     */
    function executeMilestone(
        uint256 id
    ) external override onlyGovernance nonReentrant {
        Milestone storage m = milestones[id];
        if (m.status != MilestoneStatus.Approved) revert InvalidState();

        vault.release(m.token, m.recipient, m.amount);
        m.status = MilestoneStatus.Executed;
        emit MilestoneExecuted(id);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _onlyGovernance() internal view {
        if (msg.sender != governance) revert Unauthorized();
    }
}
