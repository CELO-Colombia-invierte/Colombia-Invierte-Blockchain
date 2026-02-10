// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProjectVault} from "../../../../src/contracts/v2/core/ProjectVault.sol";
import {MockERC20} from "../../../../src/contracts/mocks/shared/MockERC20.sol";

/**
 * @notice Handler for testing the ProjectVault contract in invariants tests.
 * It simulates user interactions with the vault, such as depositing and releasing funds.
 */
contract VaultHandler is Test {
    ProjectVault public vault;
    MockERC20 public token;

    uint256 public totalDeposited;
    uint256 public totalReleased;

    constructor(ProjectVault _vault, MockERC20 _token) {
        vault = _vault;
        token = _token;

        token.mint(address(this), 1_000 ether);
        token.approve(address(vault), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACTIONS
    //////////////////////////////////////////////////////////////*/
    /** @notice Simulates a deposit action to the vault. It bounds the deposit amount to a reasonable range and updates the total deposited amount.
     * If the deposit fails (e.g., due to insufficient funds), it catches the error and does not update the total deposited.
     * @param amount The amount to deposit, which will be bounded within the function.
     */
    function deposit(uint256 amount) external {
        amount = bound(amount, 1 ether, 50 ether);

        try vault.deposit(address(token), amount) {
            totalDeposited += amount;
        } catch {}
    }

    /**
     * @notice Simulates a release action from the vault. It bounds the release amount to a reasonable range and updates the total released amount.
     * If the release fails (e.g., due to insufficient funds), it catches the error and does not update the total released.
     * @param amount The amount to release, which will be bounded within the function.
     */
    function release(uint256 amount) external {
        amount = bound(amount, 1 ether, 50 ether);

        try vault.release(address(token), address(this), amount) {
            totalReleased += amount;
        } catch {}
    }
}
