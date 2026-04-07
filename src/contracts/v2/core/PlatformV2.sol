// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {IProjectVault} from "../../../interfaces/v2/IProjectVault.sol";
import {IProjectTokenV2} from "../../../interfaces/v2/IProjectTokenV2.sol";
import {IRevenueModuleV2} from "../../../interfaces/v2/IRevenueModuleV2.sol";
import {INatilleraV2} from "../../../interfaces/v2/INatilleraV2.sol";
import {IMilestonesModule} from "../../../interfaces/v2/IMilestonesModule.sol";
import {IGovernanceModule} from "../../../interfaces/v2/IGovernanceModule.sol";
import {IDisputesModule} from "../../../interfaces/v2/IDisputesModule.sol";
import {RevenueVoting} from "../tokenization/RevenueVoting.sol";
import {NatilleraVoting} from "../natillera/NatilleraVoting.sol";

/**
 * @title PlatformV2
 * @notice Factory for creating tokenization and natillera projects via minimal clones.
 * @dev Deploys, initializes, and wires all project components in a single transaction.
 * @author Key Lab Technical Team.
 */
contract PlatformV2 {
    using Clones for address;

    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    /*//////////////////////////////////////////////////////////////
                                IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    address public immutable VAULT_IMPLEMENTATION;
    address public immutable TOKEN_IMPLEMENTATION;
    address public immutable REVENUE_IMPLEMENTATION;
    address public immutable NATILLERA_IMPLEMENTATION;
    address public immutable FEE_MANAGER;

    // Nuevas implementaciones
    address public immutable MILESTONES_IMPLEMENTATION;
    address public immutable GOVERNANCE_IMPLEMENTATION;
    address public immutable DISPUTES_IMPLEMENTATION;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    struct Project {
        address vault;
        address module;
        address token; // only for tokenization
        address milestones;
        address governance;
        address disputes;
        address creator;
    }

    uint256 public projectCount;
    mapping(uint256 => Project) public projects;

    event ProjectCreated(
        uint256 indexed id,
        string projectType,
        address vault,
        address module,
        address token,
        address milestones,
        address governance,
        address disputes
    );

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param _vault ProjectVault implementation address
     * @param _token ProjectTokenV2 implementation address
     * @param _revenue RevenueModuleV2 implementation address
     * @param _natillera NatilleraV2 implementation address
     * @param _feeManager Fee manager contract address
     * @param _milestones MilestonesModule implementation address
     * @param _governance GovernanceModule implementation address
     * @param _disputes DisputesModule implementation address
     */
    constructor(
        address _vault,
        address _token,
        address _revenue,
        address _natillera,
        address _feeManager,
        address _milestones,
        address _governance,
        address _disputes
    ) {
        if (
            _vault == address(0) ||
            _token == address(0) ||
            _revenue == address(0) ||
            _natillera == address(0) ||
            _feeManager == address(0) ||
            _milestones == address(0) ||
            _governance == address(0) ||
            _disputes == address(0)
        ) revert ZeroAddress();

        VAULT_IMPLEMENTATION = _vault;
        TOKEN_IMPLEMENTATION = _token;
        REVENUE_IMPLEMENTATION = _revenue;
        NATILLERA_IMPLEMENTATION = _natillera;
        FEE_MANAGER = _feeManager;

        MILESTONES_IMPLEMENTATION = _milestones;
        GOVERNANCE_IMPLEMENTATION = _governance;
        DISPUTES_IMPLEMENTATION = _disputes;
    }

    /*//////////////////////////////////////////////////////////////
                    TOKENIZATION PIPELINE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a complete tokenization project with all peripheral modules.
     * @dev Wires Milestones, Governance, and Disputes with appropriate Vault roles.
     */
    function createTokenizationProject(
        address settlementToken,
        uint256 fundingTarget,
        uint256 minimumCap,
        uint256 tokenPrice,
        uint256 saleDuration,
        string calldata name,
        string calldata symbol
    ) external returns (uint256 id) {
        if (settlementToken == address(0)) revert ZeroAddress();
        id = ++projectCount;

        // 1. Clones
        address vault = VAULT_IMPLEMENTATION.clone();
        address token = TOKEN_IMPLEMENTATION.clone();
        address revenue = REVENUE_IMPLEMENTATION.clone();
        address milestones = MILESTONES_IMPLEMENTATION.clone();
        address governance = GOVERNANCE_IMPLEMENTATION.clone();
        address disputes = DISPUTES_IMPLEMENTATION.clone();
        address revenueVoting = address(
            new RevenueVoting(IProjectTokenV2(token))
        );

        // 2. Initialize Core (Factory as temporary admin)
        IProjectVault(vault).initialize(
            revenue,
            address(this),
            msg.sender,
            settlementToken
        );

        uint256 maxSupply = fundingTarget / tokenPrice;
        IProjectTokenV2(token).initialize(
            name,
            symbol,
            maxSupply,
            address(this),
            revenue
        );
        IProjectTokenV2(token).setRevenueModule(revenue);

        IRevenueModuleV2(revenue).initialize(
            IRevenueModuleV2.InitParams({
                token: token,
                vault: vault,
                settlementToken: settlementToken,
                fundingTarget: fundingTarget,
                minimumCap: minimumCap,
                tokenPrice: tokenPrice,
                saleStart: block.timestamp,
                saleEnd: block.timestamp + saleDuration,
                distributionEnd: block.timestamp + saleDuration + 180 days,
                expectedApy: 0,
                governance: msg.sender,
                projectCreator: msg.sender,
                feeManager: FEE_MANAGER
            })
        );

        // 3. Initialize Peripherals
        IMilestonesModule(milestones).initialize(vault, governance);
        IGovernanceModule(governance).initialize(
            vault,
            milestones,
            revenueVoting
        );
        IDisputesModule(disputes).initialize(vault, governance);

        // 4. Role Orchestration (Wiring)
        IAccessControl(vault).grantRole(CONTROLLER_ROLE, revenue);

        // Milestones requires CONTROLLER_ROLE to release funds
        IAccessControl(vault).grantRole(CONTROLLER_ROLE, milestones);

        // Governance needs all roles to execute proposals (activate, pause, unpause, close)
        IAccessControl(vault).grantRole(GUARDIAN_ROLE, governance);
        IAccessControl(vault).grantRole(GOVERNANCE_ROLE, governance);

        // Disputes needs GUARDIAN_ROLE to freeze the vault
        IAccessControl(vault).grantRole(GUARDIAN_ROLE, disputes);

        // 5. Transfer Admin to Creator
        IAccessControl(vault).grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        IAccessControl(vault).revokeRole(DEFAULT_ADMIN_ROLE, address(this));

        IAccessControl(token).grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        IAccessControl(token).revokeRole(DEFAULT_ADMIN_ROLE, address(this));

        projects[id] = Project({
            vault: vault,
            module: revenue,
            token: token,
            milestones: milestones,
            governance: governance,
            disputes: disputes,
            creator: msg.sender
        });

        emit ProjectCreated(
            id,
            "TOKENIZATION",
            vault,
            revenue,
            token,
            milestones,
            governance,
            disputes
        );
    }

    /*//////////////////////////////////////////////////////////////
                        NATILLERA PIPELINE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a natillera project with governance and disputes.
     * @dev Omits Milestones module as it's specific to Tokenization.
     */
    function createNatilleraProject(
        address settlementToken,
        uint256 quota,
        uint256 duration,
        uint256 maxMembers
    ) external returns (uint256 id) {
        if (settlementToken == address(0)) revert ZeroAddress();
        id = ++projectCount;

        // 1. Clones
        address vault = VAULT_IMPLEMENTATION.clone();
        address natillera = NATILLERA_IMPLEMENTATION.clone();
        address governance = GOVERNANCE_IMPLEMENTATION.clone();
        address disputes = DISPUTES_IMPLEMENTATION.clone();
        address natilleraVoting = address(
            new NatilleraVoting(INatilleraV2(natillera))
        );

        // 2. Initialize Core (Factory as temporary admin)
        IProjectVault(vault).initialize(
            natillera,
            address(this),
            msg.sender,
            settlementToken
        );

        INatilleraV2(natillera).initialize(
            vault,
            FEE_MANAGER,
            settlementToken,
            quota,
            duration,
            block.timestamp,
            30 days,
            500,
            maxMembers
        );

        // 3. Initialize Peripherals (Natillera does not use Milestones)
        IGovernanceModule(governance).initialize(
            vault,
            address(0),
            natilleraVoting
        );
        IDisputesModule(disputes).initialize(vault, governance);

        // 4. Role Orchestration (Wiring)
        IAccessControl(vault).grantRole(CONTROLLER_ROLE, natillera);

        // Governance needs all roles
        IAccessControl(vault).grantRole(GUARDIAN_ROLE, governance);
        IAccessControl(vault).grantRole(GOVERNANCE_ROLE, governance);

        // Disputes needs GUARDIAN_ROLE
        IAccessControl(vault).grantRole(GUARDIAN_ROLE, disputes);

        // 5. Transfer Admin to Creator
        IAccessControl(vault).grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        IAccessControl(vault).revokeRole(DEFAULT_ADMIN_ROLE, address(this));

        projects[id] = Project({
            vault: vault,
            module: natillera,
            token: address(0),
            milestones: address(0),
            governance: governance,
            disputes: disputes,
            creator: msg.sender
        });

        emit ProjectCreated(
            id,
            "NATILLERA",
            vault,
            natillera,
            address(0),
            address(0),
            governance,
            disputes
        );
    }
}
