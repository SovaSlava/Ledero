// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAaveV3Pool} from "../../src/interfaces/external/IAaveV3Pool.sol";
import {LederoBase} from "../base/LederoBase.t.sol";
import {LederoQuoter} from "../../src/LederoQuoter.sol";
import {FfiHelper} from "./FfiHelper.t.sol";
import {OpenPositionParams, UnwindPositionParams} from "../../src/interfaces/internal/ILederoTypes.sol";
import {Mock1InchRouter} from "../mock/Mock1InchRouter.sol";
import {LeverageMath} from "../../src/libraries/LeverageMath.sol";
import {IFlashLoanAdapter} from "../../src/interfaces/internal/IFlashLoanAdapter.sol";

abstract contract AaveHelper is LederoBase, FfiHelper {
    function _helperOpenPositionAave(uint256 collateralAmount) internal {
        (uint256 flashLoanAmount, uint256 borrowAmount,) = quoter.calculateOpenParams(
            LederoQuoter.QuoteOpenParams({
                lendingAdapter: address(aaveAdapter),
                lendingPool: AAVE_POOL,
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
            lendingPool: AAVE_POOL,
            lendingAdapter: address(aaveAdapter),
            collateralToken: address(WBTC),
            borrowToken: address(USDC),
            collateralAmount: collateralAmount,
            flashLoanAmount: flashLoanAmount,
            borrowAmount: borrowAmount,
            minReturnAmount: (expectedAmount * 99) / 100, // 1% slippage
            flashAdapter: address(balancerAdapter),
            swapAdapter: address(swapAdapter),
            deadline: block.timestamp,
            swapData: swapData
        });

        vm.prank(owner);
        ledero.createLeveragedPosition(openParams);

        _verifyPositionAave(address(ledero));
    }

    function _helperUnwindPositionAave() internal {
        (uint256 collateralToWithdraw, uint256 debtAmount,) = quoter.calculateUnwindParams(
            LederoQuoter.QuoteUnwindParams({
                lendingAdapter: address(aaveAdapter),
                lendingPool: AAVE_POOL,
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
            lendingAdapter: address(aaveAdapter),
            lendingPool: AAVE_POOL,
            collateralToken: address(WBTC),
            debtToken: address(USDC),
            collateralToWithdraw: collateralToWithdraw,
            debtToRepay: debtAmount,
            minReturnAmount: (expectedUnwindReturn * 99) / 100, // 1% slippage protection
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

        assertTrue(usdcAfter > usdcBefore || wbtcAfter > wbtcBefore, "Aave Unwind: User should receive leftovers/dust");
    }

    function _helperGetDebtAAVE(address owner) internal view returns (uint256) {
        (, uint256 currentDebt,,,,) = IAaveV3Pool(AAVE_POOL).getUserAccountData(owner);
        return currentDebt;
    }

    /**
     * @notice Check position helth factor in Aave V3
     * @param _user Borrower
     */
    function _verifyPositionAave(address _user) internal view {
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,, // availableBorrowsBase
            , // currentLiquidationThreshold
            , // ltv
            uint256 healthFactor
        ) = IAaveV3Pool(AAVE_POOL).getUserAccountData(_user);

        assertTrue(totalCollateralBase > 0, "Aave: Should have collateral");
        assertTrue(totalDebtBase > 0, "Aave: Should have debt (leverage not created)");
        assertTrue(healthFactor > 1e18, "Aave: Health factor should be above 1.0");
    }

}
