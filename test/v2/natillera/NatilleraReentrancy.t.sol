// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.30;

// import {Test} from "forge-std/Test.sol";

// import {NatilleraV2} from "../../../src/contracts/v2/natillera/NatilleraV2.sol";
// import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
// import {FeeManager} from "../../../src/contracts/v2/fees/FeeManager.sol";
// import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";

// /**
//  * @title NatilleraReentrancyTest
//  * @notice Tests reentrancy protection in NatilleraV2 with fee integration.
//  */
// contract NatilleraReentrancyTest is Test {
//     NatilleraV2 natillera;
//     ProjectVault vault;
//     FeeManager feeManager;
//     MockERC20 token;

//     uint256 constant QUOTA = 100e18;
//     uint256 constant DURATION = 12;

//     Attacker attacker;

//     function setUp() public {
//         token = new MockERC20("Mock", "MOCK");

//         natillera = new NatilleraV2();
//         vault = new ProjectVault();
//         feeManager = new FeeManager();

//         feeManager.initialize(address(999)); // treasury mock

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

//         attacker = new Attacker(natillera);

//         token.mint(address(attacker), QUOTA);

//         // Attacker joins and pays
//         vm.startPrank(address(attacker));
//         token.approve(address(vault), QUOTA);
//         natillera.join();
//         natillera.payQuota(1);
//         vm.stopPrank();

//         // Mature system
//         vm.warp(block.timestamp + 400 days);

//         vault.activate();
//         vault.close();
//     }

//     /*//////////////////////////////////////////////////////////////
//                         REENTRANCY TEST
//     //////////////////////////////////////////////////////////////*/

//     /**
//      * @notice Verifies that reentrancy attack on claimFinal is prevented.
//      */
//     function test_ReentrancyAttackFails() public {
//         uint256 vaultBefore = token.balanceOf(address(vault));

//         attacker.attack();

//         uint256 vaultAfter = token.balanceOf(address(vault));

//         // Vault should be empty
//         assertEq(vaultAfter, 0);

//         // Attacker only received proportional share (after 3% fee)
//         uint256 expectedNet = (vaultBefore * 9700) / 10000;

//         assertEq(token.balanceOf(address(attacker)), expectedNet);
//         assertEq(
//             token.balanceOf(feeManager.feeTreasury()),
//             vaultBefore - expectedNet
//         );

//         // totalClaimed equals finalPool
//         assertEq(natillera.totalClaimed(), natillera.finalPool());
//     }
// }

// /*//////////////////////////////////////////////////////////////
//                         ATTACK CONTRACT
// //////////////////////////////////////////////////////////////*/

// /**
//  * @title Attacker
//  * @notice Malicious contract attempting reentrancy during claimFinal.
//  */
// contract Attacker {
//     NatilleraV2 public natillera;
//     bool internal attempted;

//     constructor(NatilleraV2 _natillera) {
//         natillera = _natillera;
//     }

//     function attack() external {
//         natillera.claimFinal();
//     }

//     // This receive is triggered when receiving tokens from vault
//     receive() external payable {
//         // Attempt reentrancy only once
//         if (!attempted) {
//             attempted = true;

//             try natillera.claimFinal() {
//                 revert("Reentrancy succeeded - should fail");
//             } catch {
//                 // Expected: should fail
//             }
//         }
//     }
// }
