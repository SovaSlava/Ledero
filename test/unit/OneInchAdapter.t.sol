// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {OneInchAdapter} from "../../src/adapters/swap/OneInch.sol";
import {Mock1InchRouter} from "../mock/Mock1InchRouter.sol";
import {MockERC20} from "../mock/MockERC20.sol";

contract OneInchAdapterTest is Test {
    OneInchAdapter oneInchAdapter;
    Mock1InchRouter router;
    MockERC20 tokenA;
    MockERC20 tokenB;
    address ledero = makeAddr("ledero");
    address hacker = makeAddr("hacker");

    function setUp() public {
        router = new Mock1InchRouter();
        oneInchAdapter = new OneInchAdapter(address(router), ledero);
        tokenA = new MockERC20("TokenA", "TKNA");
        tokenB = new MockERC20("TokenB", "TKNB");
    }

    function test_Version() public {
        uint256 adapterVersion = oneInchAdapter.getVersion();
        assertEq(adapterVersion, 1);
    }

    function test_SuccessSwapAndSendLeftOver() public {
        deal(address(tokenA), address(oneInchAdapter), 10 ether);
        deal(address(tokenB), address(router), 9 ether);
        vm.prank(ledero);
        oneInchAdapter.swap(
            address(tokenA),
            address(tokenB),
            9 ether,
            9 ether,
            abi.encodeWithSelector(Mock1InchRouter.swap.selector, tokenA, tokenB, 9 ether, address(ledero))
        );

        uint256 adapertBalance = tokenA.balanceOf(address(oneInchAdapter));
        uint256 lederoBalanceTokenIn = tokenA.balanceOf(address(ledero));
        uint256 lederoBalanceTokenOut = tokenB.balanceOf(address(ledero));
        assertEq(adapertBalance, 0);
        assertEq(lederoBalanceTokenIn, 1 ether); // 10 tokenA -> swap 9 tokenA to 9 tokenB = 1 tokenA
        assertEq(lederoBalanceTokenOut, 9 ether); // 9 tokenB
    }

    function test_RevertIf_CallToRouterFailed() public {
        deal(address(tokenA), address(oneInchAdapter), 10);
        vm.prank(ledero);
        vm.expectRevert(OneInchAdapter.SwapFailed.selector);
        oneInchAdapter.swap(address(tokenA), address(tokenB), 1, 1, "11");
    }

    function test_RevertIf_ReturnAmountLessThanMinAmount() public {
        deal(address(tokenA), address(oneInchAdapter), 10 ether);
        deal(address(tokenB), address(router), 10 ether);
        vm.prank(ledero);
        vm.expectRevert(abi.encodeWithSelector(OneInchAdapter.InsufficientReturnAmount.selector, 100 ether, 10 ether));
        oneInchAdapter.swap(
            address(tokenA),
            address(tokenB),
            10 ether,
            100 ether,
            abi.encodeWithSelector(Mock1InchRouter.swap.selector, tokenA, tokenB, 10 ether, address(ledero))
        );
    }

    function test_RevertIf_SwapNotFromLedero() public {
        vm.prank(hacker);
        vm.expectRevert(OneInchAdapter.OnlyLedero.selector);
        oneInchAdapter.swap(address(1), address(2), 1, 1, "11");
    }

    function test_RevertIf_BalanceLessThanTokenIn() public {
        vm.prank(ledero);
        vm.expectRevert(OneInchAdapter.InsufficientInput.selector);
        oneInchAdapter.swap(address(tokenA), address(2), 100, 1, "11");
    }
}
