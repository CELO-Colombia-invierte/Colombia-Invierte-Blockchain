// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from 'forge-std/Test.sol';

import {MockERC20} from '../../src/contracts/mocks/shared/MockERC20.sol';
import {PlatformV2} from '../../src/contracts/v2/core/PlatformV2.sol';
import {ProjectVault} from '../../src/contracts/v2/core/ProjectVault.sol';
import {FeeManager} from '../../src/contracts/v2/fees/FeeManager.sol';
import {FeeTreasury} from '../../src/contracts/v2/fees/FeeTreasury.sol';
import {DisputesModule} from '../../src/contracts/v2/modules/DisputesModule.sol';
import {GovernanceModule} from '../../src/contracts/v2/modules/GovernanceModule.sol';
import {MilestonesModule} from '../../src/contracts/v2/modules/MilestonesModule.sol';
import {NatilleraV2} from '../../src/contracts/v2/natillera/NatilleraV2.sol';
import {ProjectTokenV2} from '../../src/contracts/v2/tokenization/ProjectTokenV2.sol';
import {RevenueModuleV2} from '../../src/contracts/v2/tokenization/RevenueModuleV2.sol';
import {IProjectVault} from '../../src/interfaces/v2/IProjectVault.sol';

/**
 * @title BaseSetup
 * @notice Base test contract for V2 platform with all components deployed.
 * @dev Provides common setup, actors, and utilities for integration tests.
 * @author Key Lab Technical Team.
 */
contract BaseSetup is Test {
  PlatformV2 public platform;
  FeeManager public feeManager;
  FeeTreasury public treasury;
  MockERC20 public usdc;

  address public admin = address(0xA);
  address public creator = address(0xB);
  address public user1 = address(0x1);
  address public user2 = address(0x2);
  address public user3 = address(0x3);

  function setUp() public virtual {
    vm.startPrank(admin);

    usdc = new MockERC20('USD Coin', 'USDC');
    treasury = new FeeTreasury(admin);

    ProjectVault vaultImpl = new ProjectVault();
    ProjectTokenV2 tokenImpl = new ProjectTokenV2();
    RevenueModuleV2 revenueImpl = new RevenueModuleV2();
    NatilleraV2 natilleraImpl = new NatilleraV2();
    MilestonesModule milestonesImpl = new MilestonesModule();
    GovernanceModule govImpl = new GovernanceModule();
    DisputesModule disputesImpl = new DisputesModule();

    feeManager = new FeeManager();
    feeManager.initialize(address(treasury));
    feeManager.setFee(keccak256('NATILLERA_V2'), 300);
    feeManager.setFee(keccak256('TOKENIZATION_V2'), 3000);

    platform = new PlatformV2(
      address(vaultImpl),
      address(tokenImpl),
      address(revenueImpl),
      address(natilleraImpl),
      address(feeManager),
      address(milestonesImpl),
      address(govImpl),
      address(disputesImpl)
    );

    usdc.mint(user1, 100_000e18);
    usdc.mint(user2, 100_000e18);
    usdc.mint(user3, 100_000e18);

    vm.stopPrank();
  }
}
