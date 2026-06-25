// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {AaveV3Adapter, IRewardsController} from "../../src/adapters/lendings/AaveV3.sol";
import {ConstantsEtMainnet} from "../Constants.t.sol";
import {Tools} from "../utils/Tools.sol";
import {IAaveV3Pool} from "../../src/interfaces/external/IAaveV3Pool.sol";
import {Constants} from "../../src/base/Constants.sol";
import {AdapterAction} from "../../src/interfaces/internal/ILederoTypes.sol";

contract AaveV3AdapterTest is Test, ConstantsEtMainnet, Tools, Constants {
    AaveV3Adapter aaveAdapter;
    address public mockPool = makeAddr("mockPool");
    address public mockColToken = makeAddr("mockColToken");
    address public mockDebtToken = makeAddr("mockDebtToken");
    address public mockRewardContract = makeAddr("mockRewardContract");
    address public mockUser = makeAddr("mockUser");
    address public mockAToken = makeAddr("mockAToken");
    address public mockVDebtToken = makeAddr("mockVDebtToken");

    function setUp() public {
        aaveAdapter = new AaveV3Adapter();
    }

    function test_Version() public view {
        uint256 adapterVersion = aaveAdapter.getVersion();
        assertEq(adapterVersion, 1);
    }

    function test_Aave_Supply() public view {
        AdapterAction[] memory actions = aaveAdapter.supplyAndBorrow(mockPool, mockColToken, 1 ether, address(0), 0);

        bytes memory expectedCallData =
            abi.encodeWithSelector(IAaveV3Pool.supply.selector, mockColToken, 1 ether, address(this), 0);

        assertEq(actions.length, 1, "Invalid length");
        assertEq(actions[0].target, mockPool, "Invalid target contract");
        assertEq(actions[0].approveToken, mockColToken, "Approve exists");
        assertEq(actions[0].approveAmount, 1 ether, "Approve exists");
        assertEq(actions[0].callData, expectedCallData, "Invalid calldata packing");
    }

    function test_Aave_Borrow() public view {
        AdapterAction[] memory actions = aaveAdapter.supplyAndBorrow(mockPool, address(0), 0, mockDebtToken, 1 ether);

        bytes memory expectedCallData =
            abi.encodeWithSelector(IAaveV3Pool.borrow.selector, mockDebtToken, 1 ether, 2, 0, address(this));

        assertEq(actions.length, 1, "Invalid length");
        assertEq(actions[0].target, mockPool, "Invalid target contract");
        assertEq(actions[0].approveToken, address(0), "Approve exists");
        assertEq(actions[0].approveAmount, 0, "Approve exists");
        assertEq(actions[0].callData, expectedCallData, "Invalid calldata packing");
    }

    function test_Aave_Repay() public view {
        AdapterAction[] memory actions = aaveAdapter.repayAndWithdraw(mockPool, address(0), 0, mockDebtToken, 1 ether);

        bytes memory expectedCallData =
            abi.encodeWithSelector(IAaveV3Pool.repay.selector, mockDebtToken, 1 ether, 2, address(this));

        assertEq(actions.length, 1, "Invalid length");
        assertEq(actions[0].target, mockPool, "Invalid target contract");
        assertEq(actions[0].approveToken, mockDebtToken, "Approve exists");
        assertEq(actions[0].approveAmount, 1 ether, "Approve exists");
        assertEq(actions[0].callData, expectedCallData, "Invalid calldata packing");
    }

    function test_Aave_Withdraw() public view {
        AdapterAction[] memory actions = aaveAdapter.repayAndWithdraw(mockPool, mockColToken, 1 ether, address(0), 0);

        bytes memory expectedCallData =
            abi.encodeWithSelector(IAaveV3Pool.withdraw.selector, mockColToken, 1 ether, address(this));

        assertEq(actions.length, 1, "Invalid length");
        assertEq(actions[0].target, mockPool, "Invalid target contract");
        assertEq(actions[0].approveToken, address(0), "Approve exists");
        assertEq(actions[0].approveAmount, 0, "Approve exists");
        assertEq(actions[0].callData, expectedCallData, "Invalid calldata packing");
    }

    function test_Aave_ClaimProtocolRewards() public {
        IAaveV3Pool.ReserveData memory colReserve;
        colReserve.aTokenAddress = mockAToken;

        IAaveV3Pool.ReserveData memory debtReserve;
        debtReserve.variableDebtTokenAddress = mockVDebtToken;

        vm.mockCall(mockPool, abi.encodeWithSignature("getReserveData(address)", mockColToken), abi.encode(colReserve));

        vm.mockCall(
            mockPool, abi.encodeWithSignature("getReserveData(address)", mockDebtToken), abi.encode(debtReserve)
        );

        address[] memory expectedAssets = new address[](2);
        expectedAssets[0] = mockAToken;
        expectedAssets[1] = mockVDebtToken;

        bytes memory expectedCallData =
            abi.encodeWithSelector(IRewardsController.claimAllRewards.selector, expectedAssets, mockUser);

        AdapterAction[] memory actions =
            aaveAdapter.claimRewards(mockPool, mockColToken, mockDebtToken, mockRewardContract, mockUser);

        assertEq(actions.length, 1, "Invalid length");

        assertEq(actions[0].target, mockRewardContract, "Invalid target contract");
        assertEq(actions[0].approveToken, address(0), "Approve exists");
        assertEq(actions[0].approveAmount, 0, "Approve exists");
        assertEq(actions[0].callData, expectedCallData, "Invalid calldata packing");
    }

    function test_Aave_GetPositionHealthFactor() public {
        uint256 expectedHealthFactor = 1.5 * 1e18;

        vm.mockCall(
            mockPool,
            abi.encodeWithSignature("getUserAccountData(address)", mockUser),
            abi.encode(0, 0, 0, 0, 0, expectedHealthFactor)
        );

        uint256 actualHf = aaveAdapter.getPositionHealthFactor(mockPool, mockUser, mockColToken);

        assertEq(actualHf, expectedHealthFactor, "Health Factor extraction failed");
    }
}
