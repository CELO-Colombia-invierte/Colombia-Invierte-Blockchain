// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";

import {IProjectTokenV2} from "../../../interfaces/v2/IProjectTokenV2.sol";
import {IRevenueModuleV2} from "../../../interfaces/v2/IRevenueModuleV2.sol";

/**
 * @title ProjectTokenV2
 * @notice Governance token for projects with voting and supply caps.
 * @dev ERC20 with AccessControl and Votes extensions. Transfers are initially disabled.
 */
contract ProjectTokenV2 is
    Initializable,
    ERC20Upgradeable,
    ERC20VotesUpgradeable,
    AccessControlUpgradeable,
    IProjectTokenV2
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 public override maxSupply;
    bool public transfersEnabled;

    IRevenueModuleV2 public revenueModule;

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the token with name, symbol, and access control.
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param maxSupply_ Maximum total supply cap
     * @param admin_ Address with DEFAULT_ADMIN_ROLE
     * @param minter_ Address with MINTER_ROLE
     */
    function initialize(
        string calldata name_,
        string calldata symbol_,
        uint256 maxSupply_,
        address admin_,
        address minter_
    ) external initializer {
        if (admin_ == address(0) || minter_ == address(0)) {
            revert ZeroAddress();
        }

        __ERC20_init(name_, symbol_);
        __ERC20Votes_init();
        __AccessControl_init();

        maxSupply = maxSupply_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, minter_);
    }

    /*//////////////////////////////////////////////////////////////
                                MINTING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints new tokens to a specified address.
     * @dev Only callable by MINTER_ROLE. Enforces maxSupply cap.
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (totalSupply() + amount > maxSupply) {
            revert MaxSupplyExceeded();
        }

        _mint(to, amount);

        emit Minted(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Enables token transfers between non-zero addresses.
     * @dev Once enabled, transfers cannot be disabled.
     */
    function enableTransfers() external onlyRole(DEFAULT_ADMIN_ROLE) {
        transfersEnabled = true;
        emit TransfersEnabled();
    }

    /**
     * @notice Sets the revenue module for transfer hooks.
     * @param module Address of the revenue module contract
     */
    function setRevenueModule(
        address module
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (module == address(0)) revert ZeroAddress();

        revenueModule = IRevenueModuleV2(module);

        emit RevenueModuleSet(module);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Overridden to enforce transfer restrictions and trigger revenue hooks.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        // Prevent transfers until explicitly enabled (allow mint/burn)
        if (!transfersEnabled) {
            if (from != address(0) && to != address(0)) {
                revert TransfersDisabled();
            }
        }

        super._update(from, to, value);

        // Notify revenue module before transfer for potential accounting
        if (address(revenueModule) != address(0)) {
            revenueModule.beforeTokenTransfer(from, to, value);
        }
    }
}
