// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

/**
 * @title LeverageMath
 */
library LeverageMath {
    uint256 constant LEVERAGE_PRECISION = 10000;
    uint256 constant LTV_PRECISION = 10000;
    uint256 constant BORROW_SAFETY_MARGIN = 9500; // 95% from LTV

    error InvalidLeverage();
    error ZeroCollateral();
    error IncorrectLTV();

    // Calculate flashloan amount, depends on initiali amount and leverage
    function calcFlashLoanAmount(uint256 collateralAmount, uint256 desiredLeverage) internal pure returns (uint256) {
        if (collateralAmount == 0) revert ZeroCollateral();
        if (desiredLeverage <= LEVERAGE_PRECISION) revert InvalidLeverage();

        return (collateralAmount * (desiredLeverage - LEVERAGE_PRECISION)) / LEVERAGE_PRECISION;
    }

    // Calculate 95% from LTV amount for safety borrow
    function calcSafeBorrowAmount(
        uint256 totalCollateral,
        uint256 ltv,
        uint256 colPrice,
        uint256 borrowPrice,
        uint256 colDecimals,
        uint256 borrowDecimals
    ) internal pure returns (uint256) {
        uint256 colValueUSD = (totalCollateral * colPrice) / (10 ** colDecimals);
        // colValueUSD = 100$
        // LTV = 80% -> 8000
        // BORROW_SAFETY_MARGIN = 9500
        // LTV_PRECISION = 10000
        // (100 * 8000 * 9500) / (10000 * 10000) = 76$ = 95% from LTV(80%)
        uint256 safeBorrowValueUSD = (colValueUSD * ltv * BORROW_SAFETY_MARGIN) / (LTV_PRECISION * 10000);
        return (safeBorrowValueUSD * (10 ** borrowDecimals)) / borrowPrice;
    }

    // Calculating the amount of collateral that needs to be withdrawn to repay debt
    function calcCollateralToWithdraw(
        uint256 debtAmount,
        uint256 colPrice,
        uint256 debtPrice,
        uint256 colDecimals,
        uint256 debtDecimals,
        uint256 slippageBps
    ) internal pure returns (uint256) {
        if (debtAmount == 0) return 0;

        uint256 rawCollateral = (debtPrice * debtAmount * (10 ** colDecimals)) / (colPrice * (10 ** debtDecimals));

        // Add slippag0
        return (rawCollateral * (10000 + slippageBps)) / 10000;
    }

    function calcMaxLeverage(uint256 ltv) internal pure returns (uint256) {
        if (ltv > LTV_PRECISION) revert IncorrectLTV();

        uint256 safeLtv = (ltv * BORROW_SAFETY_MARGIN) / 10000;

        // 1 / (1 - safeLtv)

        return (LEVERAGE_PRECISION * LTV_PRECISION) / (LTV_PRECISION - safeLtv);
    }
}
