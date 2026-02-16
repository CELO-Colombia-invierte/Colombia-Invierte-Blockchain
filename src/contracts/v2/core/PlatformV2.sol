// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ProjectVault} from "./ProjectVault.sol";
import {IProjectVault} from "../../../interfaces/v2/IProjectVault.sol";
import {IGovernanceModule} from "../../../interfaces/v2/IGovernanceModule.sol";
import {IDisputesModule} from "../../../interfaces/v2/IDisputesModule.sol";
import {IMilestonesModule} from "../../../interfaces/v2/IMilestonesModule.sol";

contract PlatformV2 {
    using Clones for address;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

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
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProjectDeployed(
        uint256 indexed projectId,
        address vault,
        address governance,
        address disputes,
        address creator,
        address milestones
    );

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

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
