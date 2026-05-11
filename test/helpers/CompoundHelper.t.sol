// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LederoBase} from "../base/LederoBase.t.sol";
import {LederoQuoter} from "../../src/LederoQuoter.sol";
import {FfiHelper} from "./FfiHelper.t.sol";
import {OpenPositionParams, UnwindPositionParams} from "../../src/interfaces/internal/ILederoTypes.sol";
import {IComet} from "../../src/interfaces/external/ICompound.sol";
import {ILendingAdapter} from "../../src/interfaces/internal/ILendingAdapter.sol";
import {Mock1InchRouter} from "../mock/Mock1InchRouter.sol";
import {LeverageMath} from "../../src/libraries/LeverageMath.sol";
import {IFlashLoanAdapter} from "../../src/interfaces/internal/IFlashLoanAdapter.sol";

abstract contract CompoundHelper is LederoBase, FfiHelper {
    function _helperOpenPositionCompound(uint256 collateralAmount) internal {
        (uint256 flashLoanAmount, uint256 borrowAmount,) = quoter.calculateOpenParams(
            LederoQuoter.QuoteOpenParams({
                lendingAdapter: address(compoundAdapter),
                lendingPool: COMPOUND_WETH_COMET,
                flashAdapter: address(balancerAdapter),
                collateralToken: address(USDC),
                borrowToken: address(WETH),
                desiredLeverage: 30_000,
                collateralAmount: collateralAmount,
                collateralTokenPrice: 0,
                borrowTokenPrice: 0
            })
        );

        (bytes memory swapData, uint256 expectedAmount) =
            get1inchSwapData(address(WETH), address(USDC), borrowAmount, address(ledero));

        deal(address(USDC), owner, collateralAmount);

        OpenPositionParams memory openParams = OpenPositionParams({
            lendingAdapter: address(compoundAdapter),
            lendingPool: COMPOUND_WETH_COMET,
            collateralToken: address(USDC),
            borrowToken: address(WETH),
            collateralAmount: collateralAmount,
            flashLoanAmount: flashLoanAmount,
            borrowAmount: borrowAmount,
            minReturnAmount: (expectedAmount * 99) / 100,
            flashAdapter: address(balancerAdapter),
            swapAdapter: address(swapAdapter),
            deadline: block.timestamp,
            swapData: swapData
        });

        vm.prank(owner);
        ledero.createLeveragedPosition(openParams);
    }

    function _helperUnwindPositionCompound() internal {
        (uint256 collateralToWithdraw, uint256 debtAmount,) = quoter.calculateUnwindParams(
            LederoQuoter.QuoteUnwindParams({
                lendingAdapter: address(compoundAdapter),
                lendingPool: COMPOUND_WETH_COMET,
                flashAdapter: address(balancerAdapter),
                collateralToken: address(USDC),
                debtToken: address(WETH),
                user: address(ledero),
                slippageBps: 200 // 2% slippage
            })
        );

        (bytes memory unwindSwapData, uint256 expectedUnwindReturn) =
            get1inchSwapData(address(USDC), address(WETH), collateralToWithdraw, address(ledero));

        UnwindPositionParams memory unwindParams = UnwindPositionParams({
            lendingAdapter: address(compoundAdapter),
            lendingPool: COMPOUND_WETH_COMET,
            collateralToken: address(USDC),
            debtToken: address(WETH),
            collateralToWithdraw: collateralToWithdraw,
            debtToRepay: debtAmount,
            minReturnAmount: (expectedUnwindReturn * 99) / 100,
            flashAdapter: address(balancerAdapter),
            swapAdapter: address(swapAdapter),
            deadline: block.timestamp,
            swapData: unwindSwapData
        });

        uint256 usdcBefore = IERC20(address(USDC)).balanceOf(owner);
        uint256 wethBefore = IERC20(address(WETH)).balanceOf(owner);
        vm.prank(owner);
        ledero.unwindPosition(unwindParams);
        uint256 usdcAfter = IERC20(address(USDC)).balanceOf(owner);
        uint256 wethAfter = IERC20(address(WETH)).balanceOf(owner);

        assertTrue(
            usdcAfter > usdcBefore || wethAfter > wethBefore,
            "Compound Unwind: User should receive leftovers from swap dust"
        );
    }

    function _helperGetDebtCompound(address _user) internal view returns (uint256) {
        return IComet(COMPOUND_WETH_COMET).borrowBalanceOf(_user);
    }

    /**
     * @notice Check health factor in Compound
     * @param _user Borrower
     * @param _collateralAsset Collateral asset
     */
    function _verifyPositionCompound(address _user, address _collateralAsset) internal view {
        uint256 compDebt = IComet(COMPOUND_WETH_COMET).borrowBalanceOf(_user);
        uint256 compCollateral = IComet(COMPOUND_WETH_COMET).collateralBalanceOf(_user, _collateralAsset);

        assertTrue(compCollateral > 0, "Compound: Should have collateral");
        assertTrue(compDebt > 0, "Compound: Should have debt (leverage not created)");

        uint256 healthFactor = ILendingAdapter(address(compoundAdapter))
            .getPositionHealthFactor(COMPOUND_WETH_COMET, _user, _collateralAsset);

        assertTrue(healthFactor > 1e18, "Compound: Position created underwater! (HF <= 1.0)");
    }

    function _helperFixWETHCompound() internal {
        (bool successCheck, bytes memory isPausedData) =
            COMPOUND_WETH_COMET.staticcall(abi.encodeWithSignature("isWithdrawPaused()"));
        require(successCheck, "Failed to check pause status");

        bool isPaused = abi.decode(isPausedData, (bool));

        if (isPaused) {
            (bool successGov, bytes memory govData) =
                COMPOUND_WETH_COMET.staticcall(abi.encodeWithSignature("governor()"));
            require(successGov, "Failed to get governor");
            address governor = abi.decode(govData, (address));

            vm.startPrank(governor);

            (bool successPause,) = COMPOUND_WETH_COMET.call(
                abi.encodeWithSignature("pause(bool,bool,bool,bool,bool)", false, false, false, false, false)
            );
            require(successPause, "Failed to unpause Compound");
            vm.stopPrank();
        }
    }
}
