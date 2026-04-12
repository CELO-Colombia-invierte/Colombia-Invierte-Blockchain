// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

import {PlatformV2} from '../src/contracts/v2/core/PlatformV2.sol';
import {ProjectVault} from '../src/contracts/v2/core/ProjectVault.sol';
import {FeeManager} from '../src/contracts/v2/fees/FeeManager.sol';
import {FeeTreasury} from '../src/contracts/v2/fees/FeeTreasury.sol';
import {DisputesModule} from '../src/contracts/v2/modules/DisputesModule.sol';
import {GovernanceModule} from '../src/contracts/v2/modules/GovernanceModule.sol';
import {MilestonesModule} from '../src/contracts/v2/modules/MilestonesModule.sol';
import {NatilleraV2} from '../src/contracts/v2/natillera/NatilleraV2.sol';
import {ProjectTokenV2} from '../src/contracts/v2/tokenization/ProjectTokenV2.sol';
import {RevenueModuleV2} from '../src/contracts/v2/tokenization/RevenueModuleV2.sol';

/**
 * @title DeployV2
 * @notice Deployment script for V2 platform components.
 * @author Key Lab Technical Team.
 */
contract DeployV2 is Script {
  function run() external {
    uint256 deployerKey = vm.envUint('PRIVATE_KEY');
    address deployer = vm.addr(deployerKey);

    console.log('Deploying with:', deployer);

    vm.startBroadcast(deployerKey);

    /*//////////////////////////////////////////////////////////////
                            CORE & FEES
    //////////////////////////////////////////////////////////////*/

    FeeTreasury treasury = new FeeTreasury(deployer);
    console.log('FeeTreasury:', address(treasury));

    FeeManager feeManager = new FeeManager();
    feeManager.initialize(address(treasury));

    // Establecer fees iniciales
    bytes32 NATILLERA_V2 = keccak256('NATILLERA_V2');
    bytes32 TOKENIZATION_V2 = keccak256('TOKENIZATION_V2');
    feeManager.setFee(NATILLERA_V2, 300); // 3%
    feeManager.setFee(TOKENIZATION_V2, 3000); // 30%

    console.log('FeeManager:', address(feeManager));
    console.log('-> Fees configurados: Natillera 3%, Tokenization 30%');

    /*//////////////////////////////////////////////////////////////
                        IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    ProjectVault vaultImpl = new ProjectVault();
    ProjectTokenV2 tokenImpl = new ProjectTokenV2();
    RevenueModuleV2 revenueImpl = new RevenueModuleV2();
    NatilleraV2 natilleraImpl = new NatilleraV2();

    MilestonesModule milestonesImpl = new MilestonesModule();
    GovernanceModule governanceImpl = new GovernanceModule();
    DisputesModule disputesImpl = new DisputesModule();

    console.log('Vault Impl:', address(vaultImpl));
    console.log('Token Impl:', address(tokenImpl));
    console.log('Revenue Impl:', address(revenueImpl));
    console.log('Natillera Impl:', address(natilleraImpl));
    console.log('Milestones Impl:', address(milestonesImpl));
    console.log('Governance Impl:', address(governanceImpl));
    console.log('Disputes Impl:', address(disputesImpl));

    /*//////////////////////////////////////////////////////////////
                            PLATFORM
    //////////////////////////////////////////////////////////////*/

    PlatformV2 platform = new PlatformV2(
      address(vaultImpl),
      address(tokenImpl),
      address(revenueImpl),
      address(natilleraImpl),
      address(feeManager),
      address(milestonesImpl),
      address(governanceImpl),
      address(disputesImpl)
    );

    console.log('PlatformV2:', address(platform));

    vm.stopBroadcast();
  }
}
