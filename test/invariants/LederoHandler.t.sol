// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {Ledero} from "../../src/Ledero.sol";
import {OpenPositionParams, UnwindPositionParams} from "../../src/interfaces/internal/ILederoTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LeverageMath} from "../../src/libraries/LeverageMath.sol";
import {LederoOracle} from "../../src/LederoOracle.sol";
import {LederoQuoter} from "../../src/LederoQuoter.sol";
import {AaveV3Adapter} from "../../src/adapters/lendings/AaveV3.sol";
import {CompoundV3Adapter} from "../../src/adapters/lendings/CompoundV3.sol";
import {BalancerV3Adapter} from "../../src/adapters/loan/BalancerV3.sol";
import {OneInchAdapter} from "../../src/adapters/swap/OneInch.sol";
import {Mock1InchRouter} from "../mock/Mock1InchRouter.sol";
import {ConstantsEtMainnet} from "../Constants.t.sol";
import {IFlashLoanAdapter} from "../../src/interfaces/internal/IFlashLoanAdapter.sol";

interface IOracleRefresher {
    function _refreshOracleMocks() external;
}

contract LederoHandler is Test, ConstantsEtMainnet {
    Ledero public ledero;
    AaveV3Adapter public aaveAdapter;
    CompoundV3Adapter public compoundAdapter;
    BalancerV3Adapter public balancerAdapter;
    OneInchAdapter public swapAdapter;
    LederoOracle public oracle;
    LederoQuoter public quoter;
    IOracleRefresher public invariantsContract;
    bool public isPositionOpen;
    // 0 = No position 1 = Aave, 2 = Compound
    uint8 public activeProtocol;

    constructor(
        Ledero _ledero,
        AaveV3Adapter _aaveAdapter,
        CompoundV3Adapter _compoundAdapter,
        BalancerV3Adapter _balancerAdapter,
        OneInchAdapter _swapAdapter,
        LederoOracle _oracle,
        LederoQuoter _quoter,
        IOracleRefresher _invariantsContract
    ) {
        ledero = _ledero;
        aaveAdapter = _aaveAdapter;
        compoundAdapter = _compoundAdapter;
        balancerAdapter = _balancerAdapter;
        swapAdapter = _swapAdapter;
        oracle = _oracle;
        quoter = _quoter;
        invariantsContract = _invariantsContract;
    }

    function userAction_openPositionAave(uint256 rawCollateral, uint256 rawLeverage, uint256 slippageBps) public {
        if (isPositionOpen) return;

        uint256 collateralAmount = bound(rawCollateral, 0.1e8, 10e8);
        uint256 desiredLeverage = bound(rawLeverage, 15000, 50000);
        slippageBps = bound(slippageBps, 10, 500);

        deal(WBTC, address(this), collateralAmount);
        IERC20(WBTC).approve(address(ledero), collateralAmount);

        (uint256 flashLoanAmount, uint256 borrowAmount,) = quoter.calculateOpenParams(
            LederoQuoter.QuoteOpenParams({
                lendingAdapter: address(aaveAdapter),
                lendingPool: AAVE_POOL,
                flashAdapter: address(balancerAdapter),
                collateralToken: WBTC,
                borrowToken: USDC,
                desiredLeverage: desiredLeverage,
                collateralAmount: collateralAmount,
                collateralTokenPrice: 0,
                borrowTokenPrice: 0
            })
        );

        uint256 minReturnAmount = (flashLoanAmount * (10000 - slippageBps)) / 10000;

        bytes memory mockSwapData =
            abi.encodeWithSelector(Mock1InchRouter.swap.selector, USDC, WBTC, flashLoanAmount, address(ledero));

        OpenPositionParams memory params = OpenPositionParams({
            lendingPool: AAVE_POOL,
            collateralAmount: collateralAmount,
            collateralToken: WBTC,
            borrowAmount: borrowAmount,
            borrowToken: USDC,
            flashLoanAmount: flashLoanAmount,
            lendingAdapter: address(aaveAdapter),
            minReturnAmount: minReturnAmount,
            flashAdapter: address(balancerAdapter),
            swapAdapter: address(swapAdapter),
            deadline: block.timestamp + 1 hours,
            swapData: mockSwapData
        });

        (bool success,) = address(ledero).call(abi.encodeWithSelector(Ledero.createLeveragedPosition.selector, params));

        if (success) {
            isPositionOpen = true;
            activeProtocol = 1;
        }
    }

    function userAction_unwindPositionAave(uint256 rawDebtPercentage, uint256 slippageBps) public {
        if (!isPositionOpen || activeProtocol != 1) return;

        uint256 currentDebt = aaveAdapter.getDebtAmount(AAVE_POOL, address(ledero), USDC);
        if (currentDebt == 0) return;

        uint256 percent = bound(rawDebtPercentage, 1, 10000);
        uint256 debtToRepay = (currentDebt * percent) / 10000;
        if (debtToRepay == 0) return;

        slippageBps = bound(slippageBps, 10, 500);

        uint256 collateralToWithdraw = LeverageMath.calcCollateralToWithdraw(
            debtToRepay, oracle.getPrice(USDC), oracle.getPrice(WBTC), 6, 8, slippageBps
        );

        if (percent == 10000) collateralToWithdraw = type(uint256).max;

        uint256 totalFlashRepay = IFlashLoanAdapter(address(balancerAdapter)).getFullRepayAmount(USDC, debtToRepay);

        bytes memory mockSwapData =
            abi.encodeWithSelector(Mock1InchRouter.swap.selector, WBTC, USDC, totalFlashRepay, address(ledero));

        UnwindPositionParams memory params = UnwindPositionParams({
            lendingAdapter: address(aaveAdapter),
            lendingPool: AAVE_POOL,
            collateralToken: WBTC,
            debtToken: USDC,
            collateralToWithdraw: collateralToWithdraw,
            debtToRepay: debtToRepay,
            minReturnAmount: totalFlashRepay,
            flashAdapter: address(balancerAdapter),
            swapAdapter: address(swapAdapter),
            deadline: block.timestamp + 1 hours,
            swapData: mockSwapData
        });

        (bool success,) = address(ledero).call(abi.encodeWithSelector(Ledero.unwindPosition.selector, params));

        if (success && percent == 10000) {
            isPositionOpen = false;
            activeProtocol = 0;
        }
    }

    function userAction_openPositionCompound(uint256 rawCollateral, uint256 rawLeverage, uint256 slippageBps) public {
        if (isPositionOpen) return;

        uint256 collateralAmount = bound(rawCollateral, 0.1e8, 10e8);
        uint256 desiredLeverage = bound(rawLeverage, 15000, 50000);
        slippageBps = bound(slippageBps, 10, 500);

        deal(WBTC, address(this), collateralAmount);
        IERC20(WBTC).approve(address(ledero), collateralAmount);

        (uint256 flashLoanAmount, uint256 borrowAmount,) = quoter.calculateOpenParams(
            LederoQuoter.QuoteOpenParams({
                lendingAdapter: address(compoundAdapter),
                lendingPool: COMPOUND_USDC_COMET,
                flashAdapter: address(balancerAdapter),
                collateralToken: WBTC,
                borrowToken: USDC,
                desiredLeverage: desiredLeverage,
                collateralAmount: collateralAmount,
                collateralTokenPrice: 0,
                borrowTokenPrice: 0
            })
        );

        uint256 minReturnAmount = (flashLoanAmount * (10000 - slippageBps)) / 10000;

        bytes memory mockSwapData =
            abi.encodeWithSelector(Mock1InchRouter.swap.selector, USDC, WBTC, flashLoanAmount, address(ledero));

        OpenPositionParams memory params = OpenPositionParams({
            lendingPool: COMPOUND_USDC_COMET,
            collateralAmount: collateralAmount,
            collateralToken: WBTC,
            borrowAmount: borrowAmount,
            borrowToken: USDC,
            flashLoanAmount: flashLoanAmount,
            lendingAdapter: address(compoundAdapter),
            minReturnAmount: minReturnAmount,
            flashAdapter: address(balancerAdapter),
            swapAdapter: address(swapAdapter),
            deadline: block.timestamp + 1 hours,
            swapData: mockSwapData
        });

        (bool success,) = address(ledero).call(abi.encodeWithSelector(Ledero.createLeveragedPosition.selector, params));

        if (success) {
            isPositionOpen = true;
            activeProtocol = 2;
        }
    }

    function userAction_unwindPositionCompound(uint256 rawDebtPercentage, uint256 slippageBps) public {
        if (!isPositionOpen || activeProtocol != 2) return;

        uint256 currentDebt = compoundAdapter.getDebtAmount(COMPOUND_USDC_COMET, address(ledero), USDC);
        if (currentDebt == 0) return;

        uint256 percent = bound(rawDebtPercentage, 1, 10000);
        uint256 debtToRepay = (currentDebt * percent) / 10000;
        if (debtToRepay == 0) return;

        slippageBps = bound(slippageBps, 10, 500);

        uint256 collateralToWithdraw = LeverageMath.calcCollateralToWithdraw(
            debtToRepay, oracle.getPrice(USDC), oracle.getPrice(WBTC), 6, 8, slippageBps
        );

        if (percent == 10000) collateralToWithdraw = type(uint256).max;

        uint256 totalFlashRepay = IFlashLoanAdapter(address(balancerAdapter)).getFullRepayAmount(USDC, debtToRepay);

        bytes memory mockSwapData =
            abi.encodeWithSelector(Mock1InchRouter.swap.selector, WBTC, USDC, totalFlashRepay, address(ledero));

        UnwindPositionParams memory params = UnwindPositionParams({
            lendingAdapter: address(compoundAdapter),
            lendingPool: COMPOUND_USDC_COMET,
            collateralToken: WBTC,
            debtToken: USDC,
            collateralToWithdraw: collateralToWithdraw,
            debtToRepay: debtToRepay,
            minReturnAmount: totalFlashRepay,
            flashAdapter: address(balancerAdapter),
            swapAdapter: address(swapAdapter),
            deadline: block.timestamp + 1 hours,
            swapData: mockSwapData
        });

        (bool success,) = address(ledero).call(abi.encodeWithSelector(Ledero.unwindPosition.selector, params));

        if (success && percent == 10000) {
            isPositionOpen = false;
            activeProtocol = 0;
        }
    }

    function systemAction_warpTime(uint256 hoursToWarp) public {
        uint256 safeHours = bound(hoursToWarp, 1 hours, 24 * 30 hours);
        vm.warp(block.timestamp + safeHours);
        invariantsContract._refreshOracleMocks();
    }
}
