// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {FeeManager} from "../../../src/contracts/v2/fees/FeeManager.sol";
import {IFeeManager} from "../../../src/interfaces/v2/IFeeManager.sol";

/**
 * @title FeeManagerTest
 * @notice Unit tests for FeeManager configuration and fee calculations.
 */
contract FeeManagerTest is Test {
    FeeManager feeManager;

    address treasury = address(100);
    address newTreasury = address(200);

    bytes32 constant NATILLERA_V2 = keccak256("NATILLERA_V2");

    function setUp() public {
        feeManager = new FeeManager();
        feeManager.initialize(treasury);
    }

    /**
     * @notice Tests that initialize correctly sets the treasury.
     */
    function test_InitialTreasury() public view {
        assertEq(feeManager.feeTreasury(), treasury);
    }

    /**
     * @notice Tests Natillera fee calculation (3%).
     */
    function test_NatilleraFeeCalculation() public view {
        uint256 amount = 1000e18;

        (uint256 fee, uint256 net) = feeManager.calculateFee(
            feeManager.NATILLERA_V2(),
            amount
        );

        assertEq(fee, (amount * 300) / 10000);
        assertEq(net, amount - fee);
    }

    /**
     * @notice Tests Tokenization fee calculation (30%).
     */
    function test_TokenizationFeeCalculation() public view {
        uint256 amount = 1000e18;

        (uint256 fee, uint256 net) = feeManager.calculateFee(
            feeManager.TOKENIZATION_V2(),
            amount
        );

        assertEq(fee, (amount * 3000) / 10000);
        assertEq(net, amount - fee);
    }

    /**
     * @notice Tests that unconfigured fee types revert.
     */
    function test_RevertIfFeeNotConfigured() public {
        vm.expectRevert(IFeeManager.FeeNotConfigured.selector);
        feeManager.calculateFee(keccak256("UNKNOWN"), 100);
    }

    /**
     * @notice Tests that setting fee above MAX_BPS reverts.
     */
    function test_RevertIfFeeTooHigh() public {
        vm.prank(feeManager.owner());
        vm.expectRevert(IFeeManager.FeeTooHigh.selector);
        feeManager.setFee(NATILLERA_V2, 6000);
    }

    /**
     * @notice Tests updating the treasury address.
     */
    function test_SetTreasury() public {
        feeManager.setTreasury(newTreasury);
        assertEq(feeManager.feeTreasury(), newTreasury);
    }
}
