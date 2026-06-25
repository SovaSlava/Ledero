// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {CompoundV3Adapter, ICometRewards} from "../../src/adapters/lendings/CompoundV3.sol";
import {IComet} from "../../src/interfaces/external/ICompound.sol";
import {ConstantsEtMainnet} from "../Constants.t.sol";
import {Tools} from "../utils/Tools.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {Constants} from "../../src/base/Constants.sol";
import {AdapterAction} from "../../src/interfaces/internal/ILederoTypes.sol";

contract CompoundAdapterTest is Test, ConstantsEtMainnet, Tools, Constants {
    CompoundV3Adapter compoundAdapter;
    MockERC20 public mockERC20;
    address public mockPool = makeAddr("mockPool");
    address public mockUser = address(this);
    address public mockCollateral = makeAddr("mockCollateral");
    address public mockDebtToken = makeAddr("mockDebtToken");
    address mockBaseFeed = makeAddr("mockBaseFeed");
    address mockColFeed = makeAddr("mockColFeed");

    function setUp() public {
        compoundAdapter = new CompoundV3Adapter();
        mockERC20 = new MockERC20("Token", "TKN");
    }

    function test_Version() public view {
        uint256 adapterVersion = compoundAdapter.getVersion();
        assertEq(adapterVersion, 1);
    }

    function test_Compound_Supply() public view {
        AdapterAction[] memory actions =
            compoundAdapter.supplyAndBorrow(mockPool, mockCollateral, 1 ether, address(0), 0);

        bytes memory expectedCallData = abi.encodeWithSelector(IComet.supply.selector, mockCollateral, 1 ether);

        assertEq(actions.length, 1, "Invalid length");
        assertEq(actions[0].target, mockPool, "Invalid target contract");
        assertEq(actions[0].approveToken, mockCollateral, "Approve exists");
        assertEq(actions[0].approveAmount, 1 ether, "Approve exists");
        assertEq(actions[0].callData, expectedCallData, "Invalid calldata packing");
    }

    function test_Compound_Borrow() public view {
        AdapterAction[] memory actions =
            compoundAdapter.supplyAndBorrow(mockPool, address(0), 0, mockDebtToken, 1 ether);

        bytes memory expectedCallData = abi.encodeWithSelector(IComet.withdraw.selector, mockDebtToken, 1 ether);

        assertEq(actions.length, 1, "Invalid length");
        assertEq(actions[0].target, mockPool, "Invalid target contract");
        assertEq(actions[0].approveToken, address(0), "Approve exists");
        assertEq(actions[0].approveAmount, 0, "Approve exists");
        assertEq(actions[0].callData, expectedCallData, "Invalid calldata packing");
    }

    function test_Compound_Repay() public view {
        AdapterAction[] memory actions =
            compoundAdapter.repayAndWithdraw(mockPool, address(0), 0, mockDebtToken, 1 ether);

        bytes memory expectedCallData = abi.encodeWithSelector(IComet.supply.selector, mockDebtToken, 1 ether);

        assertEq(actions.length, 1, "Invalid length");
        assertEq(actions[0].target, mockPool, "Invalid target contract");
        assertEq(actions[0].approveToken, mockDebtToken, "Approve exists");
        assertEq(actions[0].approveAmount, 1 ether, "Approve exists");
        assertEq(actions[0].callData, expectedCallData, "Invalid calldata packing");
    }

    function test_Compound_Withdraw() public view {
        AdapterAction[] memory actions =
            compoundAdapter.repayAndWithdraw(mockPool, mockCollateral, 1 ether, address(0), 0);

        bytes memory expectedCallData = abi.encodeWithSelector(IComet.withdraw.selector, mockCollateral, 1 ether);

        assertEq(actions.length, 1, "Invalid length");
        assertEq(actions[0].target, mockPool, "Invalid target contract");
        assertEq(actions[0].approveToken, address(0), "Approve exists");
        assertEq(actions[0].approveAmount, 0, "Approve exists");
        assertEq(actions[0].callData, expectedCallData, "Invalid calldata packing");
    }

    function test_CompoundAdapter_ClaimProtocolRewards() public {
        address rewardContract = makeAddr("rewardContract");
        AdapterAction[] memory actions =
            compoundAdapter.claimRewards(COMPOUND_USDC_COMET, address(0), address(0), rewardContract, address(this));

        bytes memory expectedCallData = abi.encodeWithSelector(
            ICometRewards.claimTo.selector, COMPOUND_USDC_COMET, address(this), address(this), true
        );

        assertEq(actions.length, 1, "Invalid length");
        assertEq(actions[0].target, rewardContract, "Invalid swap target");
        assertEq(actions[0].approveToken, address(0), "Invalid approve token");
        assertEq(actions[0].approveAmount, 0, "Invalid approve amount");
        assertEq(actions[0].callData, expectedCallData, "Invalid callData payload");
    }

    function test_CompoundAdapter_GetPositionHealthFactor_NoDebt() public {
        vm.mockCall(mockPool, abi.encodeWithSignature("borrowBalanceOf(address)", mockUser), abi.encode(0));

        uint256 hf = compoundAdapter.getPositionHealthFactor(mockPool, mockUser, mockCollateral);
        assertEq(hf, type(uint256).max, "Should return max uint256");
    }

    function test_GetPositionHealthFactor_NormalCase() public {
        uint256 borrowAmount = 1000e6; // 1000 USDC
        uint256 borrowPrice = 1e8; // 1 $
        uint256 baseScale = 1e6; // USDC decimals

        uint256 colBalance = 1e18; // 1 Token
        uint256 colPrice = 2000e8; // 2000 $

        IComet.AssetInfo memory assetInfo = IComet.AssetInfo({
            offset: 0,
            asset: mockCollateral,
            priceFeed: mockColFeed,
            scale: 1e18,
            borrowCollateralFactor: 0,
            liquidateCollateralFactor: 0.8e18, // LT = 80%
            liquidationFactor: 0,
            supplyCap: 0
        });

        vm.mockCall(
            mockPool, abi.encodeWithSelector(IComet.borrowBalanceOf.selector, mockUser), abi.encode(borrowAmount)
        );
        vm.mockCall(
            mockPool, abi.encodeWithSelector(bytes4(keccak256("baseTokenPriceFeed()"))), abi.encode(mockBaseFeed)
        );
        vm.mockCall(mockPool, abi.encodeWithSelector(IComet.getPrice.selector, mockBaseFeed), abi.encode(borrowPrice));
        vm.mockCall(mockPool, abi.encodeWithSelector(bytes4(keccak256("baseScale()"))), abi.encode(baseScale));

        vm.mockCall(
            mockPool,
            abi.encodeWithSelector(IComet.collateralBalanceOf.selector, mockUser, mockCollateral),
            abi.encode(colBalance)
        );
        vm.mockCall(
            mockPool,
            abi.encodeWithSelector(IComet.getAssetInfoByAddress.selector, mockCollateral),
            abi.encode(assetInfo)
        );
        vm.mockCall(
            mockPool, abi.encodeWithSelector(IComet.getPrice.selector, assetInfo.priceFeed), abi.encode(colPrice)
        );

        uint256 hf = compoundAdapter.getPositionHealthFactor(mockPool, mockUser, mockCollateral);

        uint256 expectedNumerator = colBalance * colPrice * assetInfo.liquidateCollateralFactor * baseScale;
        uint256 expectedDenominator = borrowAmount * borrowPrice * assetInfo.scale;
        uint256 expectedHf = expectedNumerator / expectedDenominator;

        assertEq(hf, expectedHf, "Invalid HF returned from adapter");
    }

    function test_GetPositionHealthFactor_DustDebt_ReturnsExactHF() public {
        address user = address(this);
        address collateralAsset = mockCollateral;
        address basePriceFeed = address(0x333);
        address colPriceFeed = address(0x444);
        uint256 smallBorrowAmount = 5; // 5 wei

        vm.mockCall(
            mockPool, abi.encodeWithSelector(IComet.borrowBalanceOf.selector, user), abi.encode(smallBorrowAmount)
        );
        vm.mockCall(
            mockPool, abi.encodeWithSelector(bytes4(keccak256("baseTokenPriceFeed()"))), abi.encode(basePriceFeed)
        );

        uint256 borrowPrice = 1e8; // 1$
        vm.mockCall(mockPool, abi.encodeWithSelector(IComet.getPrice.selector, basePriceFeed), abi.encode(borrowPrice));

        uint256 baseScale = 1e6;
        vm.mockCall(mockPool, abi.encodeWithSelector(bytes4(keccak256("baseScale()"))), abi.encode(baseScale));

        uint256 colBalance = 1e18;
        vm.mockCall(
            mockPool,
            abi.encodeWithSelector(IComet.collateralBalanceOf.selector, user, collateralAsset),
            abi.encode(colBalance)
        );

        IComet.AssetInfo memory mockAssetInfo = IComet.AssetInfo({
            offset: 0,
            asset: collateralAsset,
            priceFeed: colPriceFeed,
            scale: 1e18,
            borrowCollateralFactor: 0.7e18, // LTV
            liquidateCollateralFactor: 0.8e18, // LT
            liquidationFactor: 0.9e18,
            supplyCap: 0
        });
        vm.mockCall(
            mockPool,
            abi.encodeWithSelector(IComet.getAssetInfoByAddress.selector, collateralAsset),
            abi.encode(mockAssetInfo)
        );

        uint256 colPrice = 2000e8; // 2000 $
        vm.mockCall(mockPool, abi.encodeWithSelector(IComet.getPrice.selector, colPriceFeed), abi.encode(colPrice));

        uint256 hf = compoundAdapter.getPositionHealthFactor(mockPool, user, mockCollateral);

        // numerator = 1e18 (col) * 2000e8 (price) * 0.8e18 (LCF) * 1e6 (baseScale)
        // denominator = 5 (borrow) * 1e8 (price) * 1e18 (colScale)
        uint256 expectedNumerator = colBalance * colPrice * mockAssetInfo.liquidateCollateralFactor * baseScale;
        uint256 expectedDenominator = smallBorrowAmount * borrowPrice * mockAssetInfo.scale;
        uint256 expectedHf = expectedNumerator / expectedDenominator;

        assertEq(hf, expectedHf, "Math broken for dust debt");
    }
}
