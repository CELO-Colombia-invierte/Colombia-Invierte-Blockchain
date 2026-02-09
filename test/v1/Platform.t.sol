// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Platform} from "../../src/contracts/v1/Platform.sol";
import {Natillera} from "../../src/contracts/v1/Natillera.sol";
import {Tokenizacion} from "../../src/contracts/v1/Tokenizacion.sol";
import {INatillera} from "../../src/interfaces/v1/INatillera.sol";
import {ITokenizacion} from "../../src/interfaces/v1/ITokenizacion.sol";
import {MockERC20} from "../../src/contracts/mocks/shared/MockERC20.sol";

contract PlatformTest is Test {
    /*///////////////////////////////////////////////////////////////
                                ACTORS
    //////////////////////////////////////////////////////////////*/

    address owner = address(0x1);
    address alice = address(0x2);

    /*///////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    Platform platform;
    Natillera natilleraImpl;
    Tokenizacion tokenizacionImpl;
    MockERC20 token;

    /*///////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 constant FEE = 0.01 ether;

    /*///////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() external {
        vm.startPrank(owner);

        token = new MockERC20("Mock", "MOCK");
        natilleraImpl = new Natillera();
        tokenizacionImpl = new Tokenizacion();

        platform = new Platform(
            address(natilleraImpl),
            address(tokenizacionImpl)
        );

        vm.stopPrank();
    }

    /*///////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _validNatilleraConfig()
        internal
        view
        returns (INatillera.Config memory)
    {
        return
            INatillera.Config({
                token: address(token),
                monthlyContribution: 100e18,
                totalMonths: 3,
                maxMembers: 5
            });
    }

    function _validTokenizacionConfig()
        internal
        view
        returns (ITokenizacion.Config memory)
    {
        return
            ITokenizacion.Config({
                paymentToken: address(token),
                pricePerToken: 1e18,
                totalTokens: 1_000e18,
                saleStart: block.timestamp + 1,
                saleDuration: 7 days
            });
    }

    /*///////////////////////////////////////////////////////////////
                        CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testConstructorSetsOwnerAndImplementations() external view {
        assertEq(platform.owner(), owner);
        assertEq(platform.natilleraImplementation(), address(natilleraImpl));
        assertEq(
            platform.tokenizacionImplementation(),
            address(tokenizacionImpl)
        );
    }

    function testConstructorRevertsWithZeroImplementation() external {
        vm.expectRevert(Platform.InvalidImplementation.selector);
        new Platform(address(0), address(tokenizacionImpl));

        vm.expectRevert(Platform.InvalidImplementation.selector);
        new Platform(address(natilleraImpl), address(0));
    }

    /*///////////////////////////////////////////////////////////////
                        DEPLOY NATILLERA
    //////////////////////////////////////////////////////////////*/

    function testDeployNatilleraHappyPath() external {
        vm.deal(alice, 1 ether);

        vm.prank(alice);
        address deployed = platform.deployNatillera{value: FEE}(
            block.timestamp + 1,
            _validNatilleraConfig()
        );

        assertTrue(deployed != address(0));
        assertEq(platform.totalProjects(), 1);
        assertEq(platform.getProjectById(1), deployed);
    }

    function testDeployNatilleraRefundsExcessETH() external {
        vm.deal(alice, 1 ether);
        uint256 balanceBefore = alice.balance;

        vm.prank(alice);
        platform.deployNatillera{value: 0.1 ether}(
            block.timestamp + 1,
            _validNatilleraConfig()
        );

        assertEq(alice.balance, balanceBefore - FEE, "excess ETH not refunded");
    }

    function testDeployNatilleraRevertsWithoutFee() external {
        vm.prank(alice);
        vm.expectRevert(Platform.InsufficientFee.selector);
        platform.deployNatillera(block.timestamp + 1, _validNatilleraConfig());
    }

    /*///////////////////////////////////////////////////////////////
                        DEPLOY TOKENIZACION
    //////////////////////////////////////////////////////////////*/

    function testDeployTokenizacionHappyPath() external {
        vm.deal(alice, 1 ether);

        vm.prank(alice);
        address deployed = platform.deployTokenizacion{value: FEE}(
            _validTokenizacionConfig()
        );

        assertTrue(deployed != address(0));
        assertEq(platform.totalProjects(), 1);
        assertEq(platform.getProjectById(1), deployed);
    }

    function testDeployTokenizacionRevertsWithoutFee() external {
        vm.prank(alice);
        vm.expectRevert(Platform.InsufficientFee.selector);
        platform.deployTokenizacion(_validTokenizacionConfig());
    }

    /*///////////////////////////////////////////////////////////////
                        PROJECT COUNTER
    //////////////////////////////////////////////////////////////*/

    function testTotalProjectsIncrements() external {
        vm.deal(alice, 1 ether);

        vm.startPrank(alice);

        platform.deployNatillera{value: FEE}(
            block.timestamp + 1,
            _validNatilleraConfig()
        );

        platform.deployTokenizacion{value: FEE}(_validTokenizacionConfig());

        vm.stopPrank();

        assertEq(platform.totalProjects(), 2);
    }

    /*///////////////////////////////////////////////////////////////
                        UPDATE FEE
    //////////////////////////////////////////////////////////////*/

    function testUpdateFeeOnlyOwner() external {
        vm.prank(alice);
        vm.expectRevert();
        platform.updateFee(0.02 ether);

        vm.prank(owner);
        platform.updateFee(0.02 ether);

        assertEq(platform.feeAmount(), 0.02 ether);
    }

    /*///////////////////////////////////////////////////////////////
                    UPDATE IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    function testUpdateImplementationNatillera() external {
        address newImpl = address(0x777);

        vm.prank(owner);
        platform.updateImplementation("NATILLERA", newImpl);

        assertEq(platform.natilleraImplementation(), newImpl);
    }

    function testUpdateImplementationTokenizacion() external {
        address newImpl = address(0x888);

        vm.prank(owner);
        platform.updateImplementation("TOKENIZACION", newImpl);

        assertEq(platform.tokenizacionImplementation(), newImpl);
    }

    function testUpdateImplementationRevertsInvalidType() external {
        vm.prank(owner);
        vm.expectRevert(Platform.InvalidImplementation.selector);
        platform.updateImplementation("UNKNOWN", address(0x123));
    }

    function testUpdateImplementationRevertsZeroAddress() external {
        vm.prank(owner);
        vm.expectRevert(Platform.InvalidImplementation.selector);
        platform.updateImplementation("NATILLERA", address(0));
    }

    /*///////////////////////////////////////////////////////////////
                        WITHDRAW FEES
    //////////////////////////////////////////////////////////////*/

    function testWithdrawFeesTransfersBalance() external {
        vm.deal(alice, 1 ether);

        vm.prank(alice);
        platform.deployNatillera{value: FEE}(
            block.timestamp + 1,
            _validNatilleraConfig()
        );

        uint256 ownerBalanceBefore = owner.balance;

        vm.prank(owner);
        platform.withdrawFees(payable(owner));

        assertEq(owner.balance, ownerBalanceBefore + FEE);
        assertEq(address(platform).balance, 0);
    }

    function testWithdrawFeesOnlyOwner() external {
        vm.prank(alice);
        vm.expectRevert();
        platform.withdrawFees(payable(alice));
    }
}
