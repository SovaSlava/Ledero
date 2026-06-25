// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {OneInchAdapter} from "../../src/adapters/swap/OneInch.sol";
import {Mock1InchRouter} from "../mock/Mock1InchRouter.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {AdapterAction} from "../../src/interfaces/internal/ILederoTypes.sol";

contract OneInchAdapterTest is Test {
    OneInchAdapter oneInchAdapter;
    Mock1InchRouter router;
    MockERC20 tokenA;

    function setUp() public {
        router = new Mock1InchRouter();
        oneInchAdapter = new OneInchAdapter(address(router));
        tokenA = new MockERC20("TokenA", "TKNA");
    }

    function test_Version() public view {
        uint256 adapterVersion = oneInchAdapter.getVersion();
        assertEq(adapterVersion, 1);
    }

    function test_SwapCheckAction() public view {
        AdapterAction[] memory actions = oneInchAdapter.swap(address(tokenA), 9 ether, hex"aabb");

        assertEq(actions.length, 1, "Invalid length");

        assertEq(actions[0].target, address(router), "Invalid swap target");
        assertEq(actions[0].approveToken, address(tokenA), "Invalid approve token");
        assertEq(actions[0].approveAmount, 9 ether, "Invalid approve amount");
        assertEq(actions[0].callData, hex"aabb", "Invalid callData payload");
    }
}
