// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Platform} from "../src/contracts/Platform.sol";
import {Natillera} from "../src/contracts/Natillera.sol";
import {Tokenizacion} from "../src/contracts/Tokenizacion.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy implementations
        Natillera natilleraImpl = new Natillera();
        Tokenizacion tokenizacionImpl = new Tokenizacion();

        // 2. Deploy Platform
        Platform platform = new Platform(
            address(natilleraImpl),
            address(tokenizacionImpl)
        );

        vm.stopBroadcast();

        // Log addresses for easy reference
        console.log("=========================================");
        console.log("MVP V1 DEPLOYMENT COMPLETE");
        console.log("=========================================");
        console.log("Natillera Implementation:", address(natilleraImpl));
        console.log("Tokenizacion Implementation:", address(tokenizacionImpl));
        console.log("Platform:", address(platform));
        console.log("=========================================");
        console.log("Deployment Fee:", platform.feeAmount(), "ETH");
        console.log("Owner:", vm.addr(deployerPrivateKey));
        console.log("=========================================");
    }
}
