// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Platform} from "../src/contracts/Platform.sol";
import {Natillera} from "../src/contracts/Natillera.sol";
import {Tokenizacion} from "../src/contracts/Tokenizacion.sol";

contract DeployAlfajores is Script {
    function run() external {
        // Usa la private key definida en el entorno
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Deploying with address:", deployer);

        vm.startBroadcast(deployerKey);

        // 1. Deploy implementations
        Natillera natilleraImpl = new Natillera();
        Tokenizacion tokenizacionImpl = new Tokenizacion();

        console.log("Natillera implementation:", address(natilleraImpl));
        console.log("Tokenizacion implementation:", address(tokenizacionImpl));

        // 2. Deploy Platform
        Platform platform = new Platform(
            address(natilleraImpl),
            address(tokenizacionImpl)
        );

        console.log("Platform deployed at:", address(platform));

        vm.stopBroadcast();
    }
}
