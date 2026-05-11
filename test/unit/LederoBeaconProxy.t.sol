// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {Ledero} from "../../src/Ledero.sol";
import {LederoOracle} from "../../src/LederoOracle.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {ConstantsEtMainnet} from "../Constants.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Token", "TKN") {}
}

contract LederoBeaconProxyTest is Test, ConstantsEtMainnet {
    Ledero public lederoImplementation;
    UpgradeableBeacon public beacon;
    BeaconProxy public proxy;
    Ledero public ledero;
    LederoOracle public lederoOracle;

    address public beaconOwner;
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    function setUp() public {
        beaconOwner = makeAddr("beaconOwner");

        vm.mockCall(USDC_PRICE_FEED, abi.encodeWithSignature("decimals()"), abi.encode(uint8(8)));
        vm.mockCall(WETH_PRICE_FEED, abi.encodeWithSignature("decimals()"), abi.encode(uint8(8)));

        lederoOracle = new LederoOracle();
        lederoOracle.setPriceFeed(USDC, USDC_PRICE_FEED, 86400);
        lederoOracle.setPriceFeed(WETH, WETH_PRICE_FEED, 3600);

        lederoImplementation = new Ledero();

        vm.prank(beaconOwner);
        beacon = new UpgradeableBeacon(address(lederoImplementation), beaconOwner);

        bytes memory initData = abi.encodeWithSelector(Ledero.initialize.selector);

        vm.prank(user1);
        proxy = new BeaconProxy(address(beacon), initData);

        ledero = Ledero(address(proxy));
    }

    function test_ProxyDeploymentAndInitialization() public view {
        assertEq(ledero.owner(), user1, "Wrong owner");
    }

    function test_CannotReinitialize() public {
        vm.expectRevert();
        ledero.initialize();
    }

    function test_BeaconPointsToCorrectImplementation() public view {
        assertEq(beacon.implementation(), address(lederoImplementation), "Wrong implementation");
    }

    function test_UpgradeImplementation() public {
        Ledero newImplementation = new Ledero();

        // Upgrade
        vm.prank(beaconOwner);
        beacon.upgradeTo(address(newImplementation));

        assertEq(beacon.implementation(), address(newImplementation), "Upgrade failed");
    }

    function test_MultipleProxiesShareImplementation() public {
        bytes memory initData2 = abi.encodeWithSelector(Ledero.initialize.selector);

        vm.prank(user2);
        BeaconProxy proxy2 = new BeaconProxy(address(beacon), initData2);

        Ledero ledero2 = Ledero(address(proxy2));

        assertEq(ledero.owner(), user1, "Proxy 1 wrong owner");
        assertEq(ledero2.owner(), user2, "Proxy 2 wrong owner");

        // Upgrade
        Ledero newImplementation = new Ledero();
        vm.prank(beaconOwner);
        beacon.upgradeTo(address(newImplementation));

        // Check implementation
        assertEq(beacon.implementation(), address(newImplementation), "Beacon wrong implementation");

        // Check owners after upgrade
        assertEq(ledero.owner(), user1, "Proxy 1 owner changed after upgrade");
        assertEq(ledero2.owner(), user2, "Proxy 2 owner changed after upgrade");
    }
}
