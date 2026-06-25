// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {BalancerV3Adapter, IBalancerVault} from "../../src/adapters/loan/BalancerV3.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {AdapterAction} from "../../src/interfaces/internal/ILederoTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BalancerV3AdapterTest is Test {
    BalancerV3Adapter balancerAdapter;
    MockERC20 token;
    address hacker = makeAddr("hacker");
    address vault = makeAddr("vault");

    function setUp() public {
        balancerAdapter = new BalancerV3Adapter(vault);
        token = new MockERC20("Token", "TKN");
    }

    function test_Version() public view {
        uint256 adapterVersion = balancerAdapter.getVersion();
        assertEq(adapterVersion, 1);
    }

    function test_Balancer_TakeFundsFirstStep() public view {
        AdapterAction[] memory actions = balancerAdapter.takeFundsFirstStep(address(0), 0, hex"aabb");

        bytes memory expectedCallData = abi.encodeWithSelector(IBalancerVault.unlock.selector, hex"aabb");

        assertEq(actions.length, 1, "Invalid length");
        assertEq(actions[0].target, balancerAdapter.VAULT(), "Invalid target contract");
        assertEq(actions[0].approveToken, address(0), "Approve exists");
        assertEq(actions[0].approveAmount, 0, "Approve exists");
        assertEq(actions[0].callData, expectedCallData, "Invalid calldata packing");
    }

    function test_Balancer_TakeFundsSecondStep() public view {
        AdapterAction[] memory actions = balancerAdapter.takeFundsSecondStep(address(token), 1 ether);

        bytes memory expectedCallData =
            abi.encodeWithSelector(IBalancerVault.sendTo.selector, address(token), address(this), 1 ether);

        assertEq(actions.length, 1, "Invalid length");
        assertEq(actions[0].target, balancerAdapter.VAULT(), "Invalid target contract");
        assertEq(actions[0].approveToken, address(0), "Approve exists");
        assertEq(actions[0].approveAmount, 0, "Approve exists");
        assertEq(actions[0].callData, expectedCallData, "Invalid calldata packing");
    }

    function test_Balancer_Repay() public view {
        AdapterAction[] memory actions = balancerAdapter.repayFunds(address(token), 1 ether);

        bytes memory expectedCallData0 =
            abi.encodeWithSelector(IERC20.transfer.selector, balancerAdapter.VAULT(), 1 ether);

        bytes memory expectedCallData1 = abi.encodeWithSelector(IBalancerVault.settle.selector, address(token), 1 ether);

        assertEq(actions.length, 2, "Invalid length");
        assertEq(actions[0].target, address(token), "Invalid target contract");
        assertEq(actions[0].approveToken, address(0), "Approve exists");
        assertEq(actions[0].approveAmount, 0, "Approve exists");
        assertEq(actions[0].callData, expectedCallData0, "Invalid calldata packing");
        assertEq(actions[1].target, balancerAdapter.VAULT(), "Invalid target contract");
        assertEq(actions[1].approveToken, address(0), "Approve exists");
        assertEq(actions[1].approveAmount, 0, "Approve exists");
        assertEq(actions[1].callData, expectedCallData1, "Invalid calldata packing");
    }
}
