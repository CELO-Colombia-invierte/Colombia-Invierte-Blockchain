// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.30;

// import {Test} from "forge-std/Test.sol";

// import {NatilleraV2} from "../../../src/contracts/v2/natillera/NatilleraV2.sol";
// import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
// import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";
// import {FeeManager} from "../../../src/contracts/v2/fees/FeeManager.sol";

// /**
//  * @title NatilleraPostMaturityTest
//  * @notice Tests NatilleraV2 with fee integration after maturity.
//  */
// contract NatilleraPostMaturityTest is Test {
//     NatilleraV2 natillera;
//     ProjectVault vault;
//     FeeManager feeManager;
//     MockERC20 token;

//     address treasury = address(999);

//     address alice = address(0xA11CE);
//     address bob = address(0xB0B);

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

//         token.mint(alice, QUOTA);
//         token.mint(bob, QUOTA);
//     }

//     function _joinAndPay(address user) internal {
//         vm.startPrank(user);
//         token.approve(address(vault), QUOTA);
//         natillera.join();
//         natillera.payQuota(1);
//         vm.stopPrank();
//     }

//     function _matureAndClose() internal {
//         vm.warp(block.timestamp + 400 days);
//         vault.activate();
//         vault.close();
//     }

//     /**
//      * @notice Verifies vault balance is zero after all claims and fees are accounted for.
//      */
//     function test_VaultBalanceZeroAfterAllClaims() public {
//         _joinAndPay(alice);
//         _joinAndPay(bob);

//         _matureAndClose();

//         uint256 vaultBefore = token.balanceOf(address(vault));

//         vm.prank(alice);
//         natillera.claimFinal();

//         vm.prank(bob);
//         natillera.claimFinal();

//         uint256 usersTotal = token.balanceOf(alice) + token.balanceOf(bob);

//         uint256 treasuryBalance = token.balanceOf(treasury);

//         assertEq(usersTotal + treasuryBalance, vaultBefore);
//         assertEq(token.balanceOf(address(vault)), 0);
//     }
// }
