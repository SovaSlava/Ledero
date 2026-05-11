// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {BalancerV3Adapter} from "../../src/adapters/loan/BalancerV3.sol";
import {MockERC20} from "../mock/MockERC20.sol";

contract BalancerV3AdapterTest is Test {
    BalancerV3Adapter balancerAdapter;
    MockERC20 token;
    address ledero = makeAddr("ledero");
    address hacker = makeAddr("hacker");
    address vault = makeAddr("vault");

    function setUp() public {
        balancerAdapter = new BalancerV3Adapter(vault, ledero);
        token = new MockERC20("Token", "TKN");
    }

    function test_Version() public {
        uint256 adapterVersion = balancerAdapter.getVersion();
        assertEq(adapterVersion, 1);
    }

    function test_RevertIf_ExecuteFlashLoanCallerIsNotLedero() public {
        vm.prank(hacker);
        vm.expectRevert(BalancerV3Adapter.OnlyLedero.selector);
        balancerAdapter.executeFlashLoan(address(1), 1);
    }

    function test_RevertIf_RepayFundsCallerIsNotLedero() public {
        vm.prank(hacker);
        vm.expectRevert(BalancerV3Adapter.OnlyLedero.selector);
        balancerAdapter.repayFunds(address(1), 1);
    }

    function test_RevertIf_BalancerCallbackCallerIsNotVault() public {
        vm.prank(hacker);
        vm.expectRevert(BalancerV3Adapter.OnlyVault.selector);
        balancerAdapter.balancerCallback();
    }
}
