// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.30;

// import {Test} from "forge-std/Test.sol";
// import {PlatformV2} from "../../../src/contracts/v2/core/PlatformV2.sol";
// import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
// import {RevenueModuleV2} from "../../../src/contracts/v2/tokenization/RevenueModuleV2.sol";
// import {NatilleraV2} from "../../../src/contracts/v2/natillera/NatilleraV2.sol";
// import {ProjectTokenV2} from "../../../src/contracts/v2/tokenization/ProjectTokenV2.sol";
// import {FeeManager} from "../../../src/contracts/v2/fees/FeeManager.sol";
// import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";

// /**
//  * @title PlatformTokenizationE2E
//  * @notice End-to-end tests for tokenization project flow (success and refund).
//  * @author Key Lab Technical Team.
//  */
// contract PlatformTokenizationE2E is Test {
//     PlatformV2 platform;
//     FeeManager feeManager;
//     MockERC20 usdc;

//     address alice = address(0xA1);
//     address bob = address(0xB2);

//     bytes32 internal constant REVENUE_MODULE_V2 =
//         keccak256("REVENUE_MODULE_V2");

//     function setUp() external {
//         usdc = new MockERC20("USDC", "USDC");

//         ProjectVault vaultImpl = new ProjectVault();
//         ProjectTokenV2 tokenImpl = new ProjectTokenV2();
//         RevenueModuleV2 revenueImpl = new RevenueModuleV2();
//         NatilleraV2 natilleraImpl = new NatilleraV2();
//         FeeManager feeImpl = new FeeManager();

//         feeImpl.initialize(address(this));
//         feeImpl.setFee(REVENUE_MODULE_V2, 500); // 5%

//         platform = new PlatformV2(
//             address(vaultImpl),
//             address(tokenImpl),
//             address(revenueImpl),
//             address(natilleraImpl),
//             address(feeImpl)
//         );

//         usdc.mint(alice, 1_000_000e6);
//         usdc.mint(bob, 1_000_000e6);
//     }

//     /**
//      * @notice Tests successful investment, finalization, and revenue distribution.
//      */
//     function test_E2E_SuccessfulFlow() external {
//         uint256 id = platform.createTokenizationProject(
//             address(usdc),
//             1000e6,
//             500e6,
//             100e6,
//             30 days,
//             "TestToken",
//             "TTK"
//         );

//         (address vaultAddr, address revenueAddr, , ) = platform.projects(id);

//         ProjectVault vault = ProjectVault(vaultAddr);
//         RevenueModuleV2 revenue = RevenueModuleV2(revenueAddr);

//         vm.startPrank(alice);
//         usdc.approve(revenueAddr, 500e6);
//         revenue.invest(500e6);
//         vm.stopPrank();

//         vm.startPrank(bob);
//         usdc.approve(revenueAddr, 500e6);
//         revenue.invest(500e6);
//         vm.stopPrank();

//         vm.warp(block.timestamp + 31 days);

//         vm.prank(address(revenue));
//         vault.activate();

//         revenue.finalizeSale();
//         assertEq(uint256(vault.state()), 1); // Active

//         usdc.mint(address(this), 200e6);
//         usdc.approve(revenueAddr, 200e6);
//         revenue.depositRevenue(200e6);

//         vm.prank(alice);
//         revenue.claim();

//         vm.prank(bob);
//         revenue.claim();

//         assertEq(usdc.balanceOf(alice), 999_600e6);
//         assertEq(usdc.balanceOf(bob), 999_600e6);
//     }

//     /**
//      * @notice Tests refund flow when minimum cap is not reached.
//      */
//     function test_E2E_RefundFlow() external {
//         uint256 id = platform.createTokenizationProject(
//             address(usdc),
//             1000e6,
//             900e6,
//             100e6,
//             30 days,
//             "FailToken",
//             "FTK"
//         );

//         (address vaultAddr, address revenueAddr, , ) = platform.projects(id);

//         ProjectVault vault = ProjectVault(vaultAddr);
//         RevenueModuleV2 revenue = RevenueModuleV2(revenueAddr);

//         vm.startPrank(alice);
//         usdc.approve(revenueAddr, 400e6);
//         revenue.invest(400e6);
//         vm.stopPrank();

//         vm.warp(block.timestamp + 31 days);

//         vm.prank(address(revenue));
//         vault.close();

//         vm.prank(alice);
//         revenue.refund();

//         assertEq(usdc.balanceOf(alice), 1_000_000e6);
//     }
// }
