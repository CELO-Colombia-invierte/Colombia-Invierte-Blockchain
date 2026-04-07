// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import {IVotingStrategy} from "../../../interfaces/v2/IVotingStrategy.sol";
import {INatilleraV2} from "../../../interfaces/v2/INatilleraV2.sol";

contract NatilleraVoting is IVotingStrategy {
    INatilleraV2 public natillera;

    constructor(INatilleraV2 _natillera) {
        if (address(_natillera) == address(0)) revert ZeroAddress();
        natillera = _natillera;
    }

    function getVotingPower(
        address user,
        uint256
    ) external view returns (uint256) {
        return natillera.isMember(user) ? 1 : 0;
    }
}
