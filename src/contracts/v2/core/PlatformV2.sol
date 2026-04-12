// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';

import {IDisputesModule} from '../../../interfaces/v2/IDisputesModule.sol';
import {IGovernanceModule} from '../../../interfaces/v2/IGovernanceModule.sol';
import {IMilestonesModule} from '../../../interfaces/v2/IMilestonesModule.sol';
import {INatilleraV2} from '../../../interfaces/v2/INatilleraV2.sol';
import {IProjectTokenV2} from '../../../interfaces/v2/IProjectTokenV2.sol';
import {IProjectVault} from '../../../interfaces/v2/IProjectVault.sol';
import {IRevenueModuleV2} from '../../../interfaces/v2/IRevenueModuleV2.sol';
import {NatilleraVoting} from '../natillera/NatilleraVoting.sol';
import {RevenueVoting} from '../tokenization/RevenueVoting.sol';

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
  bytes32 public constant CONTROLLER_ROLE = keccak256('CONTROLLER_ROLE');
  bytes32 public constant GUARDIAN_ROLE = keccak256('GUARDIAN_ROLE');
  bytes32 public constant GOVERNANCE_ROLE = keccak256('GOVERNANCE_ROLE');

  /*//////////////////////////////////////////////////////////////
                              IMPLEMENTATIONS
  //////////////////////////////////////////////////////////////*/

  address public immutable VAULT_IMPLEMENTATION;
  address public immutable TOKEN_IMPLEMENTATION;
  address public immutable REVENUE_IMPLEMENTATION;
  address public immutable NATILLERA_IMPLEMENTATION;
  address public immutable FEE_MANAGER;

  address public immutable MILESTONES_IMPLEMENTATION;
  address public immutable GOVERNANCE_IMPLEMENTATION;
  address public immutable DISPUTES_IMPLEMENTATION;

  /*//////////////////////////////////////////////////////////////
                              STORAGE
  //////////////////////////////////////////////////////////////*/

  struct Project {
    address vault;
    address module;
    address token;
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
      _vault == address(0) || _token == address(0) || _revenue == address(0) || _natillera == address(0)
        || _feeManager == address(0) || _milestones == address(0) || _governance == address(0)
        || _disputes == address(0)
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

    address vault = VAULT_IMPLEMENTATION.clone();
    address token = TOKEN_IMPLEMENTATION.clone();
    address revenue = REVENUE_IMPLEMENTATION.clone();
    address milestones = MILESTONES_IMPLEMENTATION.clone();
    address governance = GOVERNANCE_IMPLEMENTATION.clone();
    address disputes = DISPUTES_IMPLEMENTATION.clone();
    address revenueVoting = address(new RevenueVoting(IProjectTokenV2(token)));

    IProjectVault(vault)
      .initialize(revenue, address(this), msg.sender, settlementToken, IProjectVault.FundingModel.Revenue);

    uint256 maxSupply = fundingTarget / tokenPrice;
    IProjectTokenV2(token).initialize(name, symbol, maxSupply, address(this), revenue);
    IProjectTokenV2(token).setRevenueModule(revenue);

    IRevenueModuleV2(revenue)
      .initialize(
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
          governance: governance,
          projectCreator: msg.sender,
          feeManager: FEE_MANAGER
        })
      );

    IMilestonesModule(milestones).initialize(vault, governance, revenue);
    IGovernanceModule(governance).initialize(vault, milestones, revenueVoting, disputes);
    IDisputesModule(disputes).initialize(vault, governance);

    IAccessControl(vault).grantRole(CONTROLLER_ROLE, revenue);
    IAccessControl(vault).grantRole(CONTROLLER_ROLE, governance);
    IAccessControl(vault).grantRole(GUARDIAN_ROLE, governance);
    IAccessControl(vault).grantRole(GOVERNANCE_ROLE, governance);
    IAccessControl(vault).grantRole(GUARDIAN_ROLE, disputes);

    IAccessControl(token).grantRole(DEFAULT_ADMIN_ROLE, governance);
    IAccessControl(token).revokeRole(DEFAULT_ADMIN_ROLE, address(this));

    IAccessControl(vault).grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    IAccessControl(vault).revokeRole(DEFAULT_ADMIN_ROLE, address(this));

    projects[id] = Project({
      vault: vault,
      module: revenue,
      token: token,
      milestones: milestones,
      governance: governance,
      disputes: disputes,
      creator: msg.sender
    });

    emit ProjectCreated(id, 'TOKENIZATION', vault, revenue, token, milestones, governance, disputes);
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

    address vault = VAULT_IMPLEMENTATION.clone();
    address natillera = NATILLERA_IMPLEMENTATION.clone();
    address governance = GOVERNANCE_IMPLEMENTATION.clone();
    address disputes = DISPUTES_IMPLEMENTATION.clone();
    address natilleraVoting = address(new NatilleraVoting(INatilleraV2(natillera)));

    IProjectVault(vault)
      .initialize(natillera, address(this), msg.sender, settlementToken, IProjectVault.FundingModel.Natillera);

    INatilleraV2(natillera)
      .initialize(vault, FEE_MANAGER, settlementToken, quota, duration, block.timestamp, 30 days, 500, maxMembers);

    IGovernanceModule(governance).initialize(vault, address(0), natilleraVoting, disputes);
    IDisputesModule(disputes).initialize(vault, governance);

    IAccessControl(vault).grantRole(CONTROLLER_ROLE, governance);
    IAccessControl(vault).grantRole(GUARDIAN_ROLE, governance);
    IAccessControl(vault).grantRole(GOVERNANCE_ROLE, governance);
    IAccessControl(vault).grantRole(GUARDIAN_ROLE, disputes);

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

    emit ProjectCreated(id, 'NATILLERA', vault, natillera, address(0), address(0), governance, disputes);
  }
}
