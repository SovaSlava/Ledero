// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Script, console} from "forge-std/Script.sol";
import {Ledero} from "../src/Ledero.sol";
import {LederoOracle} from "../src/LederoOracle.sol";
import {LederoQuoter} from "../src/LederoQuoter.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {CompoundV3Adapter} from "../src/adapters/lendings/CompoundV3.sol";
import {AaveV3Adapter} from "../src/adapters/lendings/AaveV3.sol";
import {BalancerV3Adapter} from "../src/adapters/loan/BalancerV3.sol";
import {OneInchAdapter} from "../src/adapters/swap/OneInch.sol";

contract DeployLedero is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address owner = vm.addr(deployerPrivateKey);
        Ledero implementation = new Ledero();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), owner);
        BeaconProxy proxy = new BeaconProxy(address(beacon), abi.encodeWithSelector(Ledero.initialize.selector));
        address lederoCore = address(proxy);

        console.log("==================================================");
        console.log("CORE INFRASTRUCTURE:");
        console.log("Ledero Core (Proxy):", lederoCore);
        console.log("Upgradeable Beacon: ", address(beacon));
        console.log("Implementation:     ", address(implementation));

        // 2. Деплой периферии
        LederoOracle oracle = new LederoOracle();
        LederoQuoter quoter = new LederoQuoter(address(oracle));
        console.log("--------------------------------------------------");
        console.log("PERIPHERY:");
        console.log("Ledero Oracle:      ", address(oracle));
        console.log("Ledero Quoter:      ", address(quoter));

        // --- Compound (Prefix 1) ---
        bytes32 compoundSalt = getVanitySalt(type(CompoundV3Adapter).creationCode, 1);
        CompoundV3Adapter compoundAdapter = new CompoundV3Adapter{salt: compoundSalt}();
        console.log("Compound Adapter:   ", address(compoundAdapter));
        // --- Aave (Prefix 1) ---
        bytes32 aaveSalt = getVanitySalt(type(AaveV3Adapter).creationCode, 1);
        AaveV3Adapter aaveAdapter = new AaveV3Adapter{salt: aaveSalt}();
        console.log("Aave Adapter:       ", address(aaveAdapter));

        // --- Balancer (Prefix 2 + Args) ---
        bytes memory balancerInitCode = abi.encodePacked(
            type(BalancerV3Adapter).creationCode, abi.encode(vm.envAddress("BALANCER_VAULT"), lederoCore)
        );
        bytes32 flashSalt = getVanitySalt(balancerInitCode, 2);
        BalancerV3Adapter balancerAdapter =
            new BalancerV3Adapter{salt: flashSalt}(vm.envAddress("BALANCER_VAULT"), lederoCore);
        console.log("Balancer Adapter:   ", address(balancerAdapter));

        // --- 1inch (Prefix 3 + Args) ---
        bytes memory oneInchInitCode = abi.encodePacked(
            type(OneInchAdapter).creationCode, abi.encode(vm.envAddress("ONE_INCH_ROUTER"), lederoCore)
        );
        bytes32 swapSalt = getVanitySalt(oneInchInitCode, 3);
        OneInchAdapter swapAdapter = new OneInchAdapter{salt: swapSalt}(vm.envAddress("ONE_INCH_ROUTER"), lederoCore);
        console.log("1inch Adapter:      ", address(swapAdapter));
        console.log("==================================================");
        vm.stopBroadcast();
    }

    function getVanitySalt(bytes memory initCode, uint256 prefix) internal returns (bytes32) {
        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "script/CalculateAddress.ts";
        inputs[3] = vm.toString(keccak256(initCode));
        inputs[4] = vm.toString(prefix);

        bytes memory res = vm.ffi(inputs);
        return bytes32(res);
    }
}
