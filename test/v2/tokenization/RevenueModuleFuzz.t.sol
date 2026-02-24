// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.30;

// import {Test} from "forge-std/Test.sol";
// import {ProjectTokenV2} from "../../../src/contracts/v2/tokenization/ProjectTokenV2.sol";
// import {RevenueModuleV2} from "../../../src/contracts/v2/tokenization/RevenueModuleV2.sol";
// import {IRevenueModuleV2} from "../../../src/interfaces/v2/IRevenueModuleV2.sol";

// import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";
// import {MockFeeManager} from "../mocks/MockFeeManager.sol";
// import {MockVault} from "../mocks/MockVault.sol";

// contract RevenueModuleFuzz is Test {
//     ProjectTokenV2 token;
//     RevenueModuleV2 revenue;
//     MockERC20 settlement;
//     MockFeeManager feeManager;
//     MockVault vault;

//     address alice = address(0x1);
//     address bob = address(0x2);
//     address carol = address(0x3);

//     address governance = address(this);
//     address creator = address(0x5);

//     uint256 constant FUNDING_TARGET = 1_000e18;
//     uint256 constant MINIMUM_CAP = 500e18;
//     uint256 constant TOKEN_PRICE = 1e18;

//     function setUp() public {
//         settlement = new MockERC20("USDC", "USDC");
//         feeManager = new MockFeeManager();
//         vault = new MockVault(address(settlement));

//         settlement.mint(alice, 10_000_000e18);
//         settlement.mint(bob, 10_000_000e18);

//         token = new ProjectTokenV2();
//         token.initialize(
//             "ProjectToken",
//             "PT",
//             10_000_000e18,
//             governance,
//             governance
//         );

//         revenue = new RevenueModuleV2();

//         IRevenueModuleV2.InitParams memory p = IRevenueModuleV2.InitParams({
//             token: address(token),
//             vault: address(vault),
//             settlementToken: address(settlement),
//             fundingTarget: FUNDING_TARGET,
//             minimumCap: MINIMUM_CAP,
//             tokenPrice: TOKEN_PRICE,
//             saleStart: block.timestamp,
//             saleEnd: block.timestamp + 7 days,
//             distributionEnd: block.timestamp + 30 days,
//             expectedApy: 1000,
//             governance: governance,
//             projectCreator: creator,
//             feeManager: address(feeManager)
//         });

//         revenue.initialize(p);

//         token.setRevenueModule(address(revenue));
//         token.grantRole(token.MINTER_ROLE(), address(revenue));
//         token.enableTransfers();
//     }

//     function _invest(address user, uint256 amount) internal {
//         vm.startPrank(user);
//         settlement.approve(address(revenue), amount);
//         revenue.invest(amount);
//         vm.stopPrank();
//     }

//     function _closeSaleSuccessful() internal {
//         vm.warp(block.timestamp + 31 days);
//         assertEq(
//             uint256(revenue.state()),
//             uint256(IRevenueModuleV2.State.Successful)
//         );
//     }

//     /*//////////////////////////////////////////////////////////////
//                         CONSERVATION OF VALUE
//     //////////////////////////////////////////////////////////////*/

//     function testFuzz_conservationOfValue(
//         uint96 investA,
//         uint96 investB,
//         uint96 revenue1
//     ) public {
//         investA = uint96(bound(investA, MINIMUM_CAP, FUNDING_TARGET));
//         _invest(alice, investA);

//         uint256 remaining = FUNDING_TARGET - revenue.totalRaised();

//         if (remaining > 0) {
//             investB = uint96(bound(investB, 1, remaining));
//             _invest(bob, investB);
//         }

//         _closeSaleSuccessful();

//         revenue1 = uint96(bound(revenue1, 1e18, 1_000e18));

//         settlement.mint(address(this), revenue1);
//         settlement.approve(address(revenue), revenue1);
//         revenue.depositRevenue(revenue1);

//         uint256 totalPending = revenue.pending(alice) + revenue.pending(bob);

//         assertLe(totalPending, revenue1);
//     }

//     /*//////////////////////////////////////////////////////////////
//                     NO RETROACTIVE YIELD (CORRECT)
//     //////////////////////////////////////////////////////////////*/

//     function testFuzz_noRetroactiveYield(
//         uint96 investA,
//         uint96 revenue1
//     ) public {
//         investA = uint96(bound(investA, MINIMUM_CAP, FUNDING_TARGET));
//         _invest(alice, investA);

//         _closeSaleSuccessful();

//         revenue1 = uint96(bound(revenue1, 1e18, 1_000e18));

//         settlement.mint(address(this), revenue1);
//         settlement.approve(address(revenue), revenue1);
//         revenue.depositRevenue(revenue1);

//         uint256 half = token.balanceOf(alice) / 2;

//         vm.startPrank(alice);
//         bool success = token.transfer(bob, half);
//         vm.stopPrank();
//         require(success);

//         // Bob recibió tokens después del depósito
//         assertEq(revenue.pending(bob), 0);
//     }
// }
