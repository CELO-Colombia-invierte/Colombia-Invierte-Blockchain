// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ProjectVault} from "./ProjectVault.sol";
import {IProjectVault} from "../../../interfaces/v2/IProjectVault.sol";
import {IGovernanceModule} from "../../../interfaces/v2/IGovernanceModule.sol";
import {IDisputesModule} from "../../../interfaces/v2/IDisputesModule.sol";
import {IMilestonesModule} from "../../../interfaces/v2/IMilestonesModule.sol";

/**
 * @title PlatformV2
 * @notice Factory contract for deploying minimal proxy clones of all project components (vault, governance, disputes, milestones).
 * @dev Manages project creation and tracks deployed contract addresses per project ID.
 */
contract PlatformV2 {
    using Clones for address;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a new project is created.
     * @param projectId Unique identifier for the project
     * @param vault Address of the deployed ProjectVault contract
     * @param governance Address of the deployed governance module
     * @param disputes Address of the deployed disputes module
     * @param creator Address of the project creator (msg.sender)
     * @param milestones Address of the deployed milestones module
     */
    event ProjectDeployed(
        uint256 indexed projectId,
        address vault,
        address governance,
        address disputes,
        address creator,
        address milestones
    );

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Implementation contract addresses for minimal clones.
    address public immutable VAULT_IMPLEMENTATION;
    address public immutable GOVERNANCE_IMPLEMENTATION;
    address public immutable DISPUTES_IMPLEMENTATION;
    address public immutable MILESTONES_IMPLEMENTATION;

    uint256 public projectCount;

    struct ProjectContracts {
        address vault;
        address governance;
        address disputes;
        address creator;
        address milestones;
    }

    mapping(uint256 => ProjectContracts) public projects;

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the implementation contracts for all project components.
     * @param vaultImpl Address of the ProjectVault implementation
     * @param governanceImpl Address of the governance module implementation
     * @param disputesImpl Address of the disputes module implementation
     * @param milestonesImpl Address of the milestones module implementation
     */
    constructor(
        address vaultImpl,
        address governanceImpl,
        address disputesImpl,
        address milestonesImpl
    ) {
        if (
            vaultImpl == address(0) ||
            governanceImpl == address(0) ||
            disputesImpl == address(0) ||
            milestonesImpl == address(0)
        ) revert ZeroAddress();

        VAULT_IMPLEMENTATION = vaultImpl;
        GOVERNANCE_IMPLEMENTATION = governanceImpl;
        DISPUTES_IMPLEMENTATION = disputesImpl;
        MILESTONES_IMPLEMENTATION = milestonesImpl;
    }

    /*//////////////////////////////////////////////////////////////
                            PROJECT CREATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploys a full set of project contracts using minimal clones.
     * @param projectToken Address of the token used for project funding
     * @return projectId The unique ID of the newly created project
     */
    function createProject(
        address projectToken
    ) external returns (uint256 projectId) {
        if (projectToken == address(0)) revert ZeroAddress();

        projectId = ++projectCount;

        address vault = VAULT_IMPLEMENTATION.clone();
        address governance = GOVERNANCE_IMPLEMENTATION.clone();
        address disputes = DISPUTES_IMPLEMENTATION.clone();
        address milestones = MILESTONES_IMPLEMENTATION.clone();

        IProjectVault(vault).initialize(projectToken, governance, disputes);
        IGovernanceModule(governance).initialize(vault, milestones);
        IDisputesModule(disputes).initialize(vault, governance);
        IMilestonesModule(milestones).initialize(vault, governance);

        // Grant the milestones module the GOVERNANCE_ROLE on the vault.
        // This allows the milestones module to mint/burn tokens when milestones are completed.
        ProjectVault(vault).grantRole(
            ProjectVault(vault).GOVERNANCE_ROLE(),
            milestones
        );

        projects[projectId] = ProjectContracts({
            vault: vault,
            governance: governance,
            disputes: disputes,
            creator: msg.sender,
            milestones: milestones
        });

        emit ProjectDeployed(
            projectId,
            vault,
            governance,
            disputes,
            msg.sender,
            milestones
        );
    }
}
