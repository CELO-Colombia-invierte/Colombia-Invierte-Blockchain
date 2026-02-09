// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TokenizacionV2} from "../../src/contracts/v2/projects/TokenizacionV2.sol";
import {ITokenizacionV2} from "../../src/interfaces/v2/ITokenizacionV2.sol";
import {ProjectVault} from "../../src/contracts/v2/core/ProjectVault.sol";
import {MockERC20} from "../../src/contracts/mocks/shared/MockERC20.sol";

/**
 * @title TokenizacionV2Test
 * @notice Tests for the TokenizacionV2 contract.
 */
contract TokenizacionV2Test is Test {
    /// @dev The tokenization instance used for testing.
    TokenizacionV2 tokenizacion;
    /// @dev The vault instance used for testing.
    ProjectVault vault;
    /// @dev A mock ERC20 token used for testing payments.
    MockERC20 paymentToken;
    /// @dev The admin address with permissions to manage the tokenization.
    address admin = address(0xA11CE);
    /// @dev A user address that will interact with the tokenization.
    address buyer = address(0xB0B);

    /**
     * @notice Sets up the environment for the tests.
     * - Deploys the vault and tokenization contracts
     * - Grants necessary permissions
     */
    function setUp() external {
        paymentToken = new MockERC20("USD Stable", "USDS");

        ITokenizacionV2.Config memory config = ITokenizacionV2.Config({
            paymentToken: address(paymentToken),
            pricePerToken: 1 ether,
            totalTokens: 100,
            saleStart: block.timestamp,
            saleDuration: 7 days
        });

        ITokenizacionV2.ProjectInfo memory info = ITokenizacionV2.ProjectInfo({
            platform: address(this),
            projectId: 1,
            creator: address(this)
        });

        vault = new ProjectVault(address(0xDEAD), address(this));

        tokenizacion = new TokenizacionV2(config, info, address(vault));

        vault.grantRole(vault.CONTROLLER_ROLE(), address(tokenizacion));
        vault.setTokenAllowed(address(paymentToken), true);

        paymentToken.mint(buyer, 1_000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            BUY TOKENS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Tests that tokens can be bought and deposits into the vault
     */
    function testBuyTokensDepositsIntoVault() external {
        vm.startPrank(buyer);
        paymentToken.approve(address(tokenizacion), 10 ether);

        tokenizacion.buyTokens(10);

        vm.stopPrank();

        assertEq(paymentToken.balanceOf(address(vault)), 10 ether);
        assertEq(tokenizacion.tokensSold(), 10);
    }

    /**
     * @notice Tests that it is not possible to buy zero tokens
     */
    function testCannotBuyZeroAmount() external {
        vm.expectRevert(TokenizacionV2.InvalidAmount.selector);
        tokenizacion.buyTokens(0);
    }

    /**
     * @notice Tests that it is not possible to buy more tokens than available
     */
    function testCannotBuyMoreThanAvailable() external {
        vm.startPrank(buyer);
        paymentToken.approve(address(tokenizacion), 200 ether);

        vm.expectRevert(TokenizacionV2.SaleEnded.selector);
        tokenizacion.buyTokens(200);

        vm.stopPrank();
    }

    /**
     * @notice Tests that buying tokens fails if the vault does not allow the payment token
     */
    function testBuyFailsIfVaultDoesNotAllowToken() external {
        // Vault deja de permitir el token de pago real
        vault.setTokenAllowed(address(paymentToken), false);

        vm.startPrank(buyer);
        paymentToken.approve(address(tokenizacion), 10 ether);

        vm.expectRevert(ProjectVault.TokenNotAllowed.selector);
        tokenizacion.buyTokens(10);

        vm.stopPrank();
    }

    /**
     * @notice Tests that buying tokens fails before the sale start time
     */
    function testCannotBuyBeforeSaleStart() external {
        // Redeploy with future saleStart
        ITokenizacionV2.Config memory futureConfig = ITokenizacionV2.Config({
            paymentToken: address(paymentToken),
            pricePerToken: 1 ether,
            totalTokens: 100,
            saleStart: block.timestamp + 1 days,
            saleDuration: 7 days
        });

        ITokenizacionV2.ProjectInfo memory info = ITokenizacionV2.ProjectInfo({
            platform: address(this),
            projectId: 2,
            creator: admin
        });

        TokenizacionV2 futureSale = new TokenizacionV2(
            futureConfig,
            info,
            address(vault)
        );

        vm.startPrank(buyer);
        paymentToken.approve(address(futureSale), 10 ether);

        vm.expectRevert(TokenizacionV2.SaleNotActive.selector);
        futureSale.buyTokens(10);

        vm.stopPrank();
    }

    /**
     * @notice Tests that buying tokens fails after the sale end time has passed
     */
    function testCannotBuyAfterSaleEnd() external {
        // Move time AFTER sale window
        vm.warp(block.timestamp + 8 days);

        vm.startPrank(buyer);
        paymentToken.approve(address(tokenizacion), 10 ether);

        vm.expectRevert(TokenizacionV2.SaleNotActive.selector);
        tokenizacion.buyTokens(10);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            FINALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that finalizing the sale activates the vault and prevents further purchases
     */
    function testFinalizeActivatesVault() external {
        vm.startPrank(buyer);
        paymentToken.approve(address(tokenizacion), 100 ether);
        tokenizacion.buyTokens(100);
        vm.stopPrank();

        assertEq(
            uint256(vault.state()),
            uint256(ProjectVault.VaultState.Active)
        );
        assertTrue(tokenizacion.saleFinalized());
    }
}
