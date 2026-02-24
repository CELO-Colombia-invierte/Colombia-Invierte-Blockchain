// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.30;

// import {Test} from "forge-std/Test.sol";
// import {PlatformV2} from "../../../src/contracts/v2/core/PlatformV2.sol";
// import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
// import {ProjectTokenV2} from "../../../src/contracts/v2/tokenization/ProjectTokenV2.sol";
// import {RevenueModuleV2} from "../../../src/contracts/v2/tokenization/RevenueModuleV2.sol";
// import {NatilleraV2} from "../../../src/contracts/v2/natillera/NatilleraV2.sol";
// import {FeeManager} from "../../../src/contracts/v2/fees/FeeManager.sol";
// import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";

// contract PlatformNatilleraE2E is Test {
//     PlatformV2 platform;
//     MockERC20 usdc;

//     address alice = address(0xA1);
//     address bob = address(0xB2);

//     function setUp() external {
//         usdc = new MockERC20("USDC", "USDC");

//         ProjectVault vaultImpl = new ProjectVault();
//         ProjectTokenV2 tokenImpl = new ProjectTokenV2();
//         RevenueModuleV2 revenueImpl = new RevenueModuleV2();
//         NatilleraV2 natilleraImpl = new NatilleraV2();
//         FeeManager feeImpl = new FeeManager();

//         feeImpl.initialize(address(this));

//         platform = new PlatformV2(
//             address(vaultImpl),
//             address(tokenImpl),
//             address(revenueImpl),
//             address(natilleraImpl),
//             address(feeImpl)
//         );

//         usdc.mint(alice, 1000e6);
//         usdc.mint(bob, 1000e6);
//     }

//     function test_E2E_NatilleraCycle() external {
//         uint256 id = platform.createNatilleraProject(
//             address(usdc),
//             100e6,
//             3,
//             10
//         );

//         (address vaultAddr, address moduleAddr, , ) = platform.projects(id);

//         ProjectVault vault = ProjectVault(vaultAddr);
//         NatilleraV2 natillera = NatilleraV2(moduleAddr);

//         // ---- Alice ----
//         vm.startPrank(alice);
//         usdc.approve(vaultAddr, 300e6);
//         natillera.join();
//         vm.warp(block.timestamp + 31 days);
//         natillera.payQuota(1);
//         vm.stopPrank();

//         // ---- Bob ----
//         vm.startPrank(bob);
//         usdc.approve(vaultAddr, 300e6);
//         natillera.join();
//         vm.warp(block.timestamp + 31 days);
//         natillera.payQuota(1);
//         vm.stopPrank();

//         // Mature cycle
//         vm.warp(block.timestamp + 120 days);

//         // Close vault before claim
//         vm.prank(moduleAddr);
//         vault.close();

//         vm.prank(alice);
//         natillera.claimFinal();

//         assertGt(usdc.balanceOf(alice), 0);
//     }
// }
