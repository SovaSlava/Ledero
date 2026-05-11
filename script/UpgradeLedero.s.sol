// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Script, console} from "forge-std/Script.sol";
import {Ledero} from "../src/Ledero.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpgradeLederero is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("--------------------------------------------------");
        console.log(">>> ENTER BEACON ADDRESS:");

        string memory input = vm.readLine("/dev/stdin");
        address beaconAddress = vm.parseAddress(input);

        console.log("Targeting Beacon at:", beaconAddress);
        console.log("--------------------------------------------------");

        vm.startBroadcast(deployerPrivateKey);

        Ledero newImplementation = new Ledero();
        console.log("New Implementation deployed at:", address(newImplementation));

        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddress);
        beacon.upgradeTo(address(newImplementation));

        console.log("Successfully upgraded!");

        vm.stopBroadcast();
    }
}
