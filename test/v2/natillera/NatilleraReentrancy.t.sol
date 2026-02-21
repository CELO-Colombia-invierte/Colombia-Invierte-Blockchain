// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {NatilleraV2} from "../../../src/contracts/v2/natillera/NatilleraV2.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";

contract NatilleraReentrancyTest is Test {
    NatilleraV2 natillera;
    ProjectVault vault;
    MockERC20 token;

    uint256 constant QUOTA = 100e18;
    uint256 constant DURATION = 12;

    Attacker attacker;

    function setUp() public {
        token = new MockERC20("Mock", "MOCK");

        natillera = new NatilleraV2();
        vault = new ProjectVault();

        vault.initialize(address(natillera), address(this), address(this));

        vault.setTokenAllowed(address(token), true);

        natillera.initialize(
            address(vault),
            address(token),
            QUOTA,
            DURATION,
            block.timestamp
        );

        attacker = new Attacker(natillera);

        token.mint(address(attacker), QUOTA);

        // Attacker joins and pays
        vm.startPrank(address(attacker));
        token.approve(address(vault), QUOTA);
        natillera.join();
        natillera.payQuota(1);
        vm.stopPrank();

        // Mature system
        vm.warp(block.timestamp + 400 days);

        vault.activate();
        vault.close();
    }

    /*//////////////////////////////////////////////////////////////
                        REENTRANCY TEST
    //////////////////////////////////////////////////////////////*/

    function test_ReentrancyAttackFails() public {
        uint256 vaultBefore = token.balanceOf(address(vault));

        attacker.attack();

        uint256 vaultAfter = token.balanceOf(address(vault));

        // Vault debe quedar vacío
        assertEq(vaultAfter, 0);

        // Attacker solo recibió una cuota proporcional
        assertEq(token.balanceOf(address(attacker)), vaultBefore);

        // totalClaimed == finalPool
        assertEq(natillera.totalClaimed(), natillera.finalPool());
    }
}

/*//////////////////////////////////////////////////////////////
                        ATTACK CONTRACT
//////////////////////////////////////////////////////////////*/

contract Attacker {
    NatilleraV2 public natillera;
    bool internal attempted;

    constructor(NatilleraV2 _natillera) {
        natillera = _natillera;
    }

    function attack() external {
        natillera.claimFinal();
    }

    // Este receive se ejecuta cuando recibe tokens del vault
    receive() external payable {
        // Intentamos reentrar una sola vez
        if (!attempted) {
            attempted = true;

            try natillera.claimFinal() {
                revert("Reentrancy succeeded - should fail");
            } catch {
                // Esperado: debe fallar
            }
        }
    }
}
