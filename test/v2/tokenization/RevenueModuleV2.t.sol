// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.30;

// import {Test} from "forge-std/Test.sol";

// import {ProjectTokenV2} from "../../../src/contracts/v2/tokenization/ProjectTokenV2.sol";
// import {RevenueModuleV2} from "../../../src/contracts/v2/tokenization/RevenueModuleV2.sol";
// import {IRevenueModuleV2} from "../../../src/interfaces/v2/IRevenueModuleV2.sol";
// import {MockVault} from "../mocks/MockVault.sol";
// import {MockFeeManager} from "../mocks/MockFeeManager.sol";
// import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";

// contract RevenueModuleV2Test is Test {
//     ProjectTokenV2 token;
//     RevenueModuleV2 revenue;
//     MockVault vault;
//     MockFeeManager feeManager;
//     MockERC20 settlement;

//     address governance = address(this);
//     address creator = address(2);
//     address alice = address(3);

//     uint256 constant FUNDING_TARGET = 1000e18;
//     uint256 constant MINIMUM_CAP = 500e18;
//     uint256 constant TOKEN_PRICE = 1e18;

//     function setUp() public {
//         settlement = new MockERC20("USDC", "USDC");
//         vault = new MockVault(address(settlement));
//         feeManager = new MockFeeManager();

//         token = new ProjectTokenV2();
//         token.initialize("Project", "PRJ", 10_000e18, governance, governance);

//         revenue = new RevenueModuleV2();
//         IRevenueModuleV2.InitParams memory params = IRevenueModuleV2
//             .InitParams({
//                 token: address(token),
//                 vault: address(vault),
//                 settlementToken: address(settlement),
//                 fundingTarget: FUNDING_TARGET,
//                 minimumCap: MINIMUM_CAP,
//                 tokenPrice: TOKEN_PRICE,
//                 saleStart: block.timestamp,
//                 saleEnd: block.timestamp + 7 days,
//                 distributionEnd: block.timestamp + 30 days,
//                 expectedApy: 1000,
//                 governance: governance,
//                 projectCreator: creator,
//                 feeManager: address(feeManager)
//             });

//         revenue.initialize(params);

//         token.grantRole(token.MINTER_ROLE(), address(revenue));
//         token.setRevenueModule(address(revenue));
//         token.enableTransfers();

//         settlement.mint(alice, 5000e18);
//         vm.prank(alice);
//         settlement.approve(address(revenue), type(uint256).max);
//     }

//     function test_Invest_Works() public {
//         vm.prank(alice);
//         revenue.invest(100e18);

//         assertEq(token.balanceOf(alice), 100);
//         assertEq(revenue.totalRaised(), 100e18);
//     }

//     function test_SoftCapFailure() public {
//         vm.warp(block.timestamp + 8 days);
//         assertEq(uint(revenue.state()), 3); // Failed
//     }

//     function test_Refund_BurnsTokens() public {
//         vm.prank(alice);
//         revenue.invest(100e18);

//         vm.warp(block.timestamp + 8 days);

//         vm.prank(alice);
//         revenue.refund();

//         assertEq(token.balanceOf(alice), 0);
//     }

//     function test_Finalize_AppliesFee() public {
//         vm.prank(alice);
//         revenue.invest(600e18);

//         vm.warp(block.timestamp + 8 days);

//         revenue.finalizeSale();

//         // Vault balance should be drained
//         assertEq(settlement.balanceOf(address(vault)), 0);
//     }

//     function test_DepositRevenue_AndClaim() public {
//         vm.prank(alice);
//         revenue.invest(600e18);

//         vm.warp(block.timestamp + 8 days);

//         settlement.mint(address(this), 100e18);
//         settlement.approve(address(revenue), 100e18);

//         revenue.depositRevenue(100e18);

//         uint256 pending = revenue.pending(alice);
//         assertGt(pending, 0);

//         uint256 before = settlement.balanceOf(alice);

//         vm.prank(alice);
//         revenue.claim();

//         uint256 afterBal = settlement.balanceOf(alice);
//         assertGt(afterBal, before);
//     }
// }
