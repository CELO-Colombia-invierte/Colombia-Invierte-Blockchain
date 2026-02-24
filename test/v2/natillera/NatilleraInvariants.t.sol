// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.30;

// import {Test} from "forge-std/Test.sol";

// import {NatilleraV2} from "../../../src/contracts/v2/natillera/NatilleraV2.sol";
// import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
// import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";
// import {INatilleraV2} from "../../../src/interfaces/v2/INatilleraV2.sol";
// import {FeeManager} from "../../../src/contracts/v2/fees/FeeManager.sol";

// /**
//  * @title NatilleraInvariantsTest
//  * @notice Invariant tests for NatilleraV2 with fee integration.
//  */
// contract NatilleraInvariantsTest is Test {
//     NatilleraV2 natillera;
//     ProjectVault vault;
//     FeeManager feeManager;
//     MockERC20 token;

//     address treasury = address(999);

//     address[] internal members;

//     uint256 constant QUOTA = 100e18;
//     uint256 constant DURATION = 12;

//     function setUp() public {
//         token = new MockERC20("Mock", "MOCK");

//         natillera = new NatilleraV2();
//         vault = new ProjectVault();
//         feeManager = new FeeManager();

//         feeManager.initialize(treasury);

//         vault.initialize(address(natillera), address(this), address(this));
//         vault.setTokenAllowed(address(token), true);

//         natillera.initialize(
//             address(vault),
//             address(feeManager),
//             address(token),
//             QUOTA,
//             DURATION,
//             block.timestamp,
//             30 days, // paymentCycleDuration
//             500, // latePenaltyBps (5%)
//             100 // maxMembers
//         );

//         for (uint256 i = 0; i < 5; i++) {
//             address member = makeAddr(
//                 string(abi.encodePacked("member", vm.toString(i)))
//             );

//             members.push(member);

//             token.mint(member, QUOTA);

//             vm.startPrank(member);
//             token.approve(address(vault), QUOTA);
//             natillera.join();
//             natillera.payQuota(1);
//             vm.stopPrank();
//         }

//         vm.warp(block.timestamp + 400 days);

//         vault.activate();
//         vault.close();
//     }

//     /*//////////////////////////////////////////////////////////////
//         INVARIANT 1 — totalClaimed == finalPool
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @notice Verifies total claimed equals final pool after all claims.
//      */
//     function testInvariant_TotalClaimedEqualsFinalPool() public {
//         uint256 vaultBefore = token.balanceOf(address(vault));

//         for (uint256 i = 0; i < members.length; i++) {
//             vm.prank(members[i]);
//             natillera.claimFinal();
//         }

//         assertEq(natillera.totalClaimed(), vaultBefore);
//         assertEq(natillera.totalClaimed(), natillera.finalPool());
//     }

//     /*//////////////////////////////////////////////////////////////
//         INVARIANT 2 — Conservation including treasury
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @notice Verifies total value is preserved (users + treasury = initial vault).
//      */
//     function testInvariant_NoValueCreationOrLoss() public {
//         uint256 vaultBefore = token.balanceOf(address(vault));

//         uint256 usersTotal;

//         for (uint256 i = 0; i < members.length; i++) {
//             address member = members[i];

//             uint256 beforeBal = token.balanceOf(member);

//             vm.prank(member);
//             natillera.claimFinal();

//             uint256 afterBal = token.balanceOf(member);

//             usersTotal += (afterBal - beforeBal);
//         }

//         uint256 treasuryBalance = token.balanceOf(treasury);

//         assertEq(usersTotal + treasuryBalance, vaultBefore);
//         assertEq(token.balanceOf(address(vault)), 0);
//     }

//     /*//////////////////////////////////////////////////////////////
//         INVARIANT 3 — No double claim
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @notice Tests that a user cannot claim twice.
//      */
//     function testInvariant_CannotClaimTwice() public {
//         address member = members[0];

//         vm.prank(member);
//         natillera.claimFinal();

//         vm.prank(member);
//         vm.expectRevert(INatilleraV2.AlreadyClaimed.selector);
//         natillera.claimFinal();
//     }

//     /*//////////////////////////////////////////////////////////////
//         INVARIANT 4 — Claim order independent
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @notice Verifies that claim order doesn't affect final distribution.
//      */
//     function testInvariant_RandomClaimOrder() public {
//         uint256 vaultBefore = token.balanceOf(address(vault));

//         for (uint256 i = members.length; i > 0; i--) {
//             vm.prank(members[i - 1]);
//             natillera.claimFinal();
//         }

//         assertEq(token.balanceOf(address(vault)), 0);
//         assertEq(natillera.totalClaimed(), vaultBefore);
//     }
// }
