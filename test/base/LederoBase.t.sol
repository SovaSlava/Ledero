// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {Ledero} from "../../src/Ledero.sol";
import {LederoOracle} from "../../src/LederoOracle.sol";
import {LederoQuoter} from "../../src/LederoQuoter.sol";

import {AaveV3Adapter} from "../../src/adapters/lendings/AaveV3.sol";
import {CompoundV3Adapter} from "../../src/adapters/lendings/CompoundV3.sol";
import {BalancerV3Adapter} from "../../src/adapters/loan/BalancerV3.sol";
import {OneInchAdapter} from "../../src/adapters/swap/OneInch.sol";
import {ConstantsEtMainnet} from "../Constants.t.sol";
import {Tools} from "../utils/Tools.sol";
import {Constants} from "../../src/base/Constants.sol";

abstract contract LederoBase is Test, ConstantsEtMainnet, Tools, Constants {
    // Core
    Ledero public lederoImplementation;
    UpgradeableBeacon public beacon;
    BeaconProxy public proxy;
    Ledero public ledero;

    // Periphery
    LederoOracle public oracle;
    LederoQuoter public quoter;

    // Adapters
    AaveV3Adapter public aaveAdapter;
    CompoundV3Adapter public compoundAdapter;
    BalancerV3Adapter public balancerAdapter;
    OneInchAdapter public swapAdapter;

    // Users
    address public admin = address(this);
    address public owner = makeAddr("owner");

    function setUp() public virtual {
        _deployOracle();
        _deployCore();
        _deployLendingAdapters();
        _deployFlashAndSwapAdapters();
        _setupPermissions();
    }

    function _deployOracle() internal virtual {
        oracle = new LederoOracle();
        oracle.setPriceFeed(USDC, USDC_PRICE_FEED, 86400);
        oracle.setPriceFeed(WBTC, WBTC_PRICE_FEED, 86400);
    }

    function _deployCore() internal virtual {
        // Proxy
        lederoImplementation = new Ledero();
        beacon = new UpgradeableBeacon(address(lederoImplementation), admin);
        bytes memory initData = abi.encodeWithSelector(Ledero.initialize.selector);
        proxy = new BeaconProxy(address(beacon), initData);
        ledero = Ledero(address(proxy));

        // Quoter
        quoter = new LederoQuoter(address(oracle));
    }

    function _deployLendingAdapters() internal virtual {
        AaveV3Adapter tempAave = new AaveV3Adapter();
        CompoundV3Adapter tempCompound = new CompoundV3Adapter();
        aaveAdapter = AaveV3Adapter(_etchToVanity(address(tempAave), LENDING_PREFIX, 1));
        compoundAdapter = CompoundV3Adapter(_etchToVanity(address(tempCompound), LENDING_PREFIX, 2));
    }

    function _deployFlashAndSwapAdapters() internal virtual {
        BalancerV3Adapter tempBalancer = new BalancerV3Adapter(BALANCER_V3_VAULT);
        OneInchAdapter tempSwap = new OneInchAdapter(INCH_ROUTER);
        balancerAdapter = BalancerV3Adapter(_etchToVanity(address(tempBalancer), FLASH_PREFIX, 3));
        swapAdapter = OneInchAdapter(_etchToVanity(address(tempSwap), SWAP_PREFIX, 4));
    }

    function _setupPermissions() internal virtual {
        // Transfer ownership
        ledero.transferOwnership(owner);

        vm.startPrank(owner);
        ledero.acceptOwnership();
        IERC20(USDC).approve(address(ledero), type(uint256).max);
        IERC20(WBTC).approve(address(ledero), type(uint256).max);
        vm.stopPrank();
    }
}
