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
                lendingPool: COMPOUND_USDC_COMET,
                flashAdapter: address(balancerAdapter),
                collateralToken: address(WBTC),
                borrowToken: address(USDC),
                desiredLeverage: 30_000,
                collateralAmount: collateralAmount,
                collateralTokenPrice: 0,
                borrowTokenPrice: 0
            })
        );

        (bytes memory swapData, uint256 expectedAmount) =
            get1inchSwapData(address(USDC), address(WBTC), borrowAmount, address(ledero));

        deal(address(WBTC), owner, collateralAmount);

        OpenPositionParams memory openParams = OpenPositionParams({
            lendingAdapter: address(compoundAdapter),
            lendingPool: COMPOUND_USDC_COMET,
            collateralToken: address(WBTC),
            borrowToken: address(USDC),
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
                lendingPool: COMPOUND_USDC_COMET,
                flashAdapter: address(balancerAdapter),
                collateralToken: address(WBTC),
                debtToken: address(USDC),
                user: address(ledero),
                slippageBps: 200 // 2% slippage
            })
        );

        (bytes memory unwindSwapData, uint256 expectedUnwindReturn) =
            get1inchSwapData(address(WBTC), address(USDC), collateralToWithdraw, address(ledero));

        UnwindPositionParams memory unwindParams = UnwindPositionParams({
            lendingAdapter: address(compoundAdapter),
            lendingPool: COMPOUND_USDC_COMET,
            collateralToken: address(WBTC),
            debtToken: address(USDC),
            collateralToWithdraw: collateralToWithdraw,
            debtToRepay: debtAmount,
            minReturnAmount: (expectedUnwindReturn * 99) / 100,
            flashAdapter: address(balancerAdapter),
            swapAdapter: address(swapAdapter),
            deadline: block.timestamp,
            swapData: unwindSwapData
        });

        uint256 usdcBefore = IERC20(address(USDC)).balanceOf(owner);
        uint256 wbtcBefore = IERC20(address(WBTC)).balanceOf(owner);
        vm.prank(owner);
        ledero.unwindPosition(unwindParams);
        uint256 usdcAfter = IERC20(address(USDC)).balanceOf(owner);
        uint256 wbtcAfter = IERC20(address(WBTC)).balanceOf(owner);

        assertTrue(
            usdcAfter > usdcBefore || wbtcAfter > wbtcBefore,
            "Compound Unwind: User should receive leftovers from swap dust"
        );
    }

    function _helperGetDebtCompound(address _user) internal view returns (uint256) {
        return IComet(COMPOUND_USDC_COMET).borrowBalanceOf(_user);
    }

    /**
     * @notice Check health factor in Compound
     * @param _user Borrower
     * @param _collateralAsset Collateral asset
     */
    function _verifyPositionCompound(address _user, address _collateralAsset) internal view {
        uint256 compDebt = IComet(COMPOUND_USDC_COMET).borrowBalanceOf(_user);
        uint256 compCollateral = IComet(COMPOUND_USDC_COMET).collateralBalanceOf(_user, _collateralAsset);

        assertTrue(compCollateral > 0, "Compound: Should have collateral");
        assertTrue(compDebt > 0, "Compound: Should have debt (leverage not created)");

        uint256 healthFactor = ILendingAdapter(address(compoundAdapter))
            .getPositionHealthFactor(COMPOUND_USDC_COMET, _user, _collateralAsset);

        assertTrue(healthFactor > 1e18, "Compound: Position created underwater! (HF <= 1.0)");
    }

}
