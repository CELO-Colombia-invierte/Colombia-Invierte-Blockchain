// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IProjectTokenV2
 * @notice Interface for the project governance token with supply caps and transfer controls.
 * @author Key Lab Technical Team.
 */
interface IProjectTokenV2 {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error TransfersDisabled();
    error MaxSupplyExceeded();
    error ZeroAddress();
    error ZeroAmount();
    error AlreadySet();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event RevenueModuleSet(address indexed module);
    event TransfersEnabled();
    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function initialize(
        string calldata name_,
        string calldata symbol_,
        uint256 maxSupply_,
        address admin_,
        address minter_
    ) external;

    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function enableTransfers() external;

    function setRevenueModule(address module) external;

    function maxSupply() external view returns (uint256);

    function balanceOf(address user) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function getPastVotes(
        address account,
        uint256 blockNumber
    ) external view returns (uint256);
}
