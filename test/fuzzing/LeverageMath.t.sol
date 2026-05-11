// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test, console} from "forge-std/Test.sol";
import {LeverageMath} from "../../src/libraries/LeverageMath.sol";

contract LeverageMathFuzzTest is Test {
function testFuzz_CalcSafeBorrowAmount_Invariants(
        uint256 collateralAmount,
        uint256 ltv,
        uint256 colDecimals,
        uint256 borrowDecimals,
        uint256 colPrice,
        uint256 borrowPrice
    ) public {
        colDecimals = bound(colDecimals, 6, 18);
        borrowDecimals = bound(borrowDecimals, 6, 18);
        ltv = bound(ltv, 5000, 9000);
        colPrice = bound(colPrice, 1e6, 100_000e8);
        borrowPrice = bound(borrowPrice, 1e6, 100_000e8);
        collateralAmount = bound(collateralAmount, 100 * (10 ** colDecimals), 10_000_000 * (10 ** colDecimals));

        uint256 safeBorrow = LeverageMath.calcSafeBorrowAmount(
            collateralAmount, ltv, colPrice, borrowPrice, colDecimals, borrowDecimals
        );

        uint256 colValueUSD = (collateralAmount * colPrice) / (10 ** colDecimals);
        uint256 maxBorrowValueUSD = (colValueUSD * ltv) / 10000;
        uint256 maxBorrow = (maxBorrowValueUSD * (10 ** borrowDecimals)) / borrowPrice;

        assertTrue(safeBorrow <= maxBorrow, "Safe borrow exceeds absolute LTV limit");

        uint256 expectedSafeBorrow = (maxBorrow * 9500) / 10000;
        
        uint256 absDelta = safeBorrow > expectedSafeBorrow ? safeBorrow - expectedSafeBorrow : expectedSafeBorrow - safeBorrow;
        
        bool isValid = absDelta <= 10 || (absDelta * 1e18) / (expectedSafeBorrow == 0 ? 1 : expectedSafeBorrow) <= 1e14;
        
        assertTrue(isValid, "Safety margin applied incorrectly due to math truncation");
    }

    function testFuzz_CalcFlashLoanAmount_Precision(uint256 collateralAmount, uint256 desiredLeverage) public {
        collateralAmount = bound(collateralAmount, 100e6, 1_000_000e6);
        desiredLeverage = bound(desiredLeverage, 15000, 100000);

        uint256 flashLoanAmount = LeverageMath.calcFlashLoanAmount(collateralAmount, desiredLeverage);
        uint256 totalPositionSize = collateralAmount + flashLoanAmount;

        uint256 actualLeverage = (totalPositionSize * 10000) / collateralAmount;

        assertApproxEqAbs(actualLeverage, desiredLeverage, 1, "Leverage math precision loss");
    }

    function testFuzz_CalcMaxLeverage(uint256 ltv) public {
        ltv = bound(ltv, 1000, 9000); 
        
        uint256 maxLev = LeverageMath.calcMaxLeverage(ltv);
        uint256 safeLtv = (ltv * 9500) / 10000; // BORROW_SAFETY_MARGIN

        // maxLev * (1 - safeLtv) == 1
        // maxLev * (10000 - safeLtv) / 10000 == 10000
        uint256 derivedPrecision = (maxLev * (10000 - safeLtv)) / 10000;
        
        assertApproxEqAbs(derivedPrecision, 10000, 5, "Max leverage math invariant failed");
    }

function testFuzz_CalcCollateralToWithdraw_Precision(
        uint256 debtAmount,
        uint256 colDecimals,
        uint256 debtDecimals,
        uint256 colPrice,
        uint256 debtPrice,
        uint256 slippageBps
    ) public {
        colDecimals = bound(colDecimals, 6, 18);
        debtDecimals = bound(debtDecimals, 6, 18);
        colPrice = bound(colPrice, 1e6, 100_000e8);
        debtPrice = bound(debtPrice, 1e6, 100_000e8);
        debtAmount = bound(debtAmount, 10 * (10 ** debtDecimals), 1_000_000 * (10 ** debtDecimals));
        slippageBps = bound(slippageBps, 0, 1000); 

        uint256 colToWithdraw = LeverageMath.calcCollateralToWithdraw(
            debtAmount, colPrice, debtPrice, colDecimals, debtDecimals, slippageBps
        );

        uint256 withdrawnColValueUSD = (colToWithdraw * colPrice) / (10 ** colDecimals);
        uint256 debtValueUSD = (debtAmount * debtPrice) / (10 ** debtDecimals);
        uint256 expectedDebtValueWithSlippage = (debtValueUSD * (10000 + slippageBps)) / 10000;

        uint256 absDelta = withdrawnColValueUSD > expectedDebtValueWithSlippage 
            ? withdrawnColValueUSD - expectedDebtValueWithSlippage 
            : expectedDebtValueWithSlippage - withdrawnColValueUSD;
            
        bool isValid = absDelta <= 1e8 || 
            (absDelta * 1e18) / (expectedDebtValueWithSlippage == 0 ? 1 : expectedDebtValueWithSlippage) <= 2e14;
            
        assertTrue(isValid, "Withdrawn collateral value precision loss exceeds limits");
    }
}
