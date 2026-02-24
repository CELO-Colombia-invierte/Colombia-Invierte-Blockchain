// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {PlatformV2} from "../../../src/contracts/v2/core/PlatformV2.sol";
import {ProjectVault} from "../../../src/contracts/v2/core/ProjectVault.sol";
import {ProjectTokenV2} from "../../../src/contracts/v2/tokenization/ProjectTokenV2.sol";
import {RevenueModuleV2} from "../../../src/contracts/v2/tokenization/RevenueModuleV2.sol";
import {NatilleraV2} from "../../../src/contracts/v2/natillera/NatilleraV2.sol";
import {DisputesModule} from "../../../src/contracts/v2/modules/DisputesModule.sol";
import {GovernanceModule} from "../../../src/contracts/v2/modules/GovernanceModule.sol";
import {MilestonesModule} from "../../../src/contracts/v2/modules/MilestonesModule.sol";
import {FeeManager} from "../../../src/contracts/v2/fees/FeeManager.sol";
import {FeeTreasury} from "../../../src/contracts/v2/fees/FeeTreasury.sol";
import {MockERC20} from "../../../src/contracts/mocks/shared/MockERC20.sol";

/*//////////////////////////////////////////////////////////////
                        INTEGRATION TEST
//////////////////////////////////////////////////////////////*/

/**
 * @title IntegrationTest
 * @notice Comprehensive integration tests for V2 platform components.
 * @author Key Lab Technical Team.
 */
contract IntegrationTest is Test {
    PlatformV2 internal platform;
    FeeManager internal feeManager;
    FeeTreasury internal treasury;

    ProjectVault internal vaultImpl;
    ProjectTokenV2 internal tokenImpl;
    RevenueModuleV2 internal revenueImpl;
    NatilleraV2 internal natilleraImpl;
    MilestonesModule internal milestonesImpl;
    GovernanceModule internal governanceImpl;
    DisputesModule internal disputesImpl;

    MockERC20 internal usdc;

    address internal owner = address(1);
    address internal alice = address(2);

    function setUp() public {
        vm.startPrank(owner);

        treasury = new FeeTreasury(owner);

        feeManager = new FeeManager();
        feeManager.initialize(address(treasury));

        // Deploy Core Implementations
        vaultImpl = new ProjectVault();
        tokenImpl = new ProjectTokenV2();
        revenueImpl = new RevenueModuleV2();
        natilleraImpl = new NatilleraV2();

        // Deploy Peripheral Modules Implementations
        milestonesImpl = new MilestonesModule();
        governanceImpl = new GovernanceModule();
        disputesImpl = new DisputesModule();

        platform = new PlatformV2(
            address(vaultImpl),
            address(tokenImpl),
            address(revenueImpl),
            address(natilleraImpl),
            address(feeManager),
            address(milestonesImpl),
            address(governanceImpl),
            address(disputesImpl)
        );

        vm.stopPrank();

        usdc = new MockERC20("Mock USDC", "mUSDC");
        usdc.mint(alice, 1_000e6);
    }

    /*//////////////////////////////////////////////////////////////
                    TOKENIZATION HAPPY PATH
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests successful tokenization flow: invest, finalize, activate.
     */
    function test_Tokenization_FullFlow() public {
        vm.prank(owner);
        uint256 id = platform.createTokenizationProject(
            address(usdc),
            1_000e6,
            500e6,
            1e6,
            7 days,
            "TestToken",
            "TT"
        );

        // Project mapping now returns 7 fields
        (
            address vaultAddr,
            address moduleAddr,
            address tokenAddr,
            ,
            ,
            ,

        ) = platform.projects(id);

        RevenueModuleV2 revenue = RevenueModuleV2(moduleAddr);
        ProjectVault vault = ProjectVault(vaultAddr);
        ProjectTokenV2 token = ProjectTokenV2(tokenAddr);

        vm.startPrank(alice);
        usdc.approve(moduleAddr, 500e6);
        revenue.invest(500e6);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 500);

        vm.warp(block.timestamp + 8 days);

        // Revenue module is already authorized by the Platform to call activate()
        vm.prank(owner);
        revenue.finalizeSale();

        assertEq(
            uint256(vault.state()),
            uint256(ProjectVault.VaultState.Active)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            REFUND FLOW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests refund when minimum cap is not reached.
     */
    function test_Refund_Flow() public {
        vm.prank(owner);
        uint256 id = platform.createTokenizationProject(
            address(usdc),
            1_000e6,
            900e6, // High minimum cap to force failure
            1e6,
            7 days,
            "TestToken",
            "TT"
        );

        (, address moduleAddr, , , , , ) = platform.projects(id);
        RevenueModuleV2 revenue = RevenueModuleV2(moduleAddr);

        vm.startPrank(alice);
        usdc.approve(moduleAddr, 500e6);
        revenue.invest(500e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);

        vm.prank(alice);
        revenue.refund();

        assertEq(usdc.balanceOf(alice), 1_000e6);
    }

    /*//////////////////////////////////////////////////////////////
                            NATILLERA FLOW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests natillera lifecycle: join, pay, mature, claim.
     */
    function test_Natillera_Flow() public {
        vm.prank(owner);
        uint256 id = platform.createNatilleraProject(
            address(usdc),
            100e6,
            3,
            10
        );

        (address vaultAddr, address moduleAddr, , , , , ) = platform.projects(
            id
        );

        NatilleraV2 natillera = NatilleraV2(moduleAddr);
        ProjectVault vault = ProjectVault(vaultAddr);

        vm.prank(alice);
        natillera.join();

        vm.startPrank(alice);
        usdc.approve(vaultAddr, 300e6);
        natillera.payQuota(1);
        vm.stopPrank();

        vm.warp(block.timestamp + 100 days);

        // Owner (Creator) has DEFAULT_ADMIN_ROLE, so they grant themselves CONTROLLER_ROLE to close the vault manually
        vm.startPrank(owner);
        vault.grantRole(vault.CONTROLLER_ROLE(), owner);
        vault.close();
        vm.stopPrank();

        vm.prank(alice);
        natillera.claimFinal();

        assertGt(usdc.balanceOf(alice), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        DISPUTE RESTRICTED
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Verifies non-governance cannot open disputes.
     */
    function test_Dispute_Restricted() public {
        DisputesModule disputes = new DisputesModule();

        vm.prank(owner);
        disputes.initialize(address(0x1234), owner);

        vm.prank(alice);
        vm.expectRevert();
        disputes.openDispute("grief");
    }
}
