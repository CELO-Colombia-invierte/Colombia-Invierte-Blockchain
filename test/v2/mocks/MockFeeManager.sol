// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract MockFeeManager {
    uint16 public feeBps = 300; // 3%

    function calculateFee(
        bytes32,
        uint256 amount
    ) external view returns (uint256 fee, uint256 net) {
        fee = (amount * feeBps) / 10000;
        net = amount - fee;
    }

    function feeTreasury() external pure returns (address) {
        return address(0xdead);
    }
}
