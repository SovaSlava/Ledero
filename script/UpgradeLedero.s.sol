// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Script, console} from "forge-std/Script.sol";
import {Ledero} from "../src/Ledero.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpgradeLedero is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address beaconAddress = vm.envAddress("BEACON_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        Ledero newImplementation = new Ledero();
        console.log("New Implementation deployed at:", address(newImplementation));
        vm.writeFile("deployed_impl.txt", vm.toString(address(newImplementation)));

        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddress);
        beacon.upgradeTo(address(newImplementation));

        console.log("Successfully upgraded!");

        vm.stopBroadcast();
    }
}
