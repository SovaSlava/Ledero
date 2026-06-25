// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {LeverageMath} from "../../src/libraries/LeverageMath.sol";

contract LeverageMathWrapper {
    function calcFlashLoanAmount(uint256 collateral, uint256 desiredLeverage) public pure returns (uint256) {
        return LeverageMath.calcFlashLoanAmount(collateral, desiredLeverage);
    }

    function calcMaxLeverage(uint256 ltv) public pure returns (uint256) {
        return LeverageMath.calcMaxLeverage(ltv);
    }

    function calcSafeBorrowAmount(
        uint256 collateralAmount,
        uint256 ltv,
        uint256 colPrice,
        uint256 borrowPrice,
        uint256 colDecimals,
        uint256 borrowDecimals
    ) public pure returns (uint256) {
        return LeverageMath.calcSafeBorrowAmount(
            collateralAmount, ltv, colPrice, borrowPrice, colDecimals, borrowDecimals
        );
    }

    function calcCollateralToWithdraw(
        uint256 debtAmount,
        uint256 colPrice,
        uint256 debtPrice,
        uint256 colDecimals,
        uint256 debtDecimals,
        uint256 slippageBps
    ) public pure returns (uint256) {
        return LeverageMath.calcCollateralToWithdraw(
            debtAmount, colPrice, debtPrice, colDecimals, debtDecimals, slippageBps
        );
    }
}

contract LeverageMathRevertsTest is Test {
    LeverageMathWrapper libMath;

    function setUp() public {
        libMath = new LeverageMathWrapper();
    }

    function test_CalcFlashLoanAmount() public view {
        uint256 collateral = 1e8; // 1 WBTC
        uint256 desiredLeverage = 30000; // 3x leverage
        uint256 expectedFlashLoan = 2e8; // 2 WBTC

        uint256 actualFlashLoan = libMath.calcFlashLoanAmount(collateral, desiredLeverage);

        assertEq(actualFlashLoan, expectedFlashLoan, "Flash loan amount mismatch");
    }

    function test_CalcMaxLeverage_Positive() public view {
        // Formula: (10000 * 10000) / (10000 - 7600) = 100000000 / 2400 = 41666 (4.16x)
        uint256 ltv = 8000; // 80%
        // BORROW_SAFETY_MARGIN = 95%
        // SafeLtv = 8000 * 0.95 = 7600
        // MaxLeverage = (10000 * 10000) / (10000 - 7600) = 100000000 / 2400 = 41666 = 4.16 leverage
        uint256 expectedMaxLeverage = 41666;

        uint256 actualMaxLeverage = libMath.calcMaxLeverage(ltv);

        assertEq(actualMaxLeverage, expectedMaxLeverage, "Max leverage calculation is wrong");
    }

    function test_CalcSafeBorrowAmount() public view {
        uint256 collateralAmount = 1e8; // 1 WBTC
        uint256 ltv = 8000; // 80%

        uint256 colPrice = 65000e8; // 1 WBTC = $65,000
        uint256 borrowPrice = 1e8; // 1 USDC = 1$

        // Expected result:
        // Collateral value = 65000 $
        // Max debt for 80% LTV = 52000 $
        // Safe debt (95%) = 49400 $ = 49,400 USDC
        uint256 expectedSafeBorrow = 49400e6; // USDC 6 decimals

        uint256 actualSafeBorrow = libMath.calcSafeBorrowAmount(collateralAmount, ltv, colPrice, borrowPrice, 8, 6);

        assertEq(actualSafeBorrow, expectedSafeBorrow, "Safe borrow amount mismatch");
    }

    function test_CalcCollateralToWithdraw() public view {
        uint256 debtToRepay = 13000e6; // Debt = 13000 USDC

        uint256 colPrice = 65000e8; // 1 WBTC = 65000 $
        uint256 borrowPrice = 1e8; // 1 USDC = 1$

        uint256 slippageBps = 0;

        // Expected result:
        // Need to sell part of collateral for receive 13000 USDC.
        // When 1 WBTC = 65000 $, we need sell  0.2 WBTC
        // 13000 / 65000 = 0.2
        uint256 expectedCollateralToWithdraw = 0.2e8; // 0.2 WBTC

        uint256 actualCollateral =
            libMath.calcCollateralToWithdraw(debtToRepay, colPrice, borrowPrice, 8, 6, slippageBps);

        assertEq(actualCollateral, expectedCollateralToWithdraw, "Collateral to withdraw mismatch");
    }

    function test_CalcCollateralToWithdraw_ZeroDeb() public view {
        uint256 actualCollateral = libMath.calcCollateralToWithdraw(0, 1, 2, 18, 6, 1000);
        assertEq(actualCollateral, 0, "Collateral to withdraw mismatch");
    }

    // Negative paths
    function test_RevertIf_InvalidLeverage() public {
        vm.expectRevert(LeverageMath.InvalidLeverage.selector);
        libMath.calcFlashLoanAmount(1000e6, 9000);
    }

    function test_RevertIf_CollateralIsZero() public {
        vm.expectRevert(LeverageMath.ZeroCollateral.selector);
        libMath.calcFlashLoanAmount(0, 0);
    }

    function test_RevertIf_LTVMoreThan100Percent() public {
        vm.expectRevert(LeverageMath.IncorrectLTV.selector);
        libMath.calcMaxLeverage(40000); // 400%
    }
}
