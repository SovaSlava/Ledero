// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {LeverageMath} from "./libraries/LeverageMath.sol";
import {ILendingAdapter} from "./interfaces/internal/ILendingAdapter.sol";
import {IFlashLoanAdapter} from "./interfaces/internal/IFlashLoanAdapter.sol";
import {LederoOracle} from "./LederoOracle.sol";
import {ILederoErrors} from "./interfaces/internal/ILederoErrors.sol";

/**
 * @title Ledero Quoter
 * @notice Helper contract to calculate position sizes, flashloans, and debts for the frontend.
 */
contract LederoQuoter is ILederoErrors {
    LederoOracle public immutable ORACLE;

    /**
     * @notice Parameters for calculating a leveraged position opening
     */
    struct QuoteOpenParams {
        address lendingAdapter; // Address of the lending adapter (e.g., AaveV3Adapter)
        address flashAdapter; // Address of the flash loan adapter (e.g., BalancerV2Adapter)
        address lendingPool; // Address of the lending liquidity pool (e.g., Aave Pool)
        address collateralToken; // Token supplied by the user as margin (e.g., WBTC)
        address borrowToken; // Token borrowed from the lending protocol for leverage (e.g., USDC)
        uint256 desiredLeverage; // Target leverage multiplied (e.g., 3e18 for 3x)
        uint256 collateralAmount; // User's initial margin amount (in collateral token decimals)
        uint256 collateralTokenPrice; // Collateral price (8 decimals); set to 0 to fetch from oracle
        uint256 borrowTokenPrice; // Borrow token price (8 decimals); set to 0 to fetch from oracle
    }

    /**
     * @notice Parameters for calculating a position unwind (closing)
     */
    struct QuoteUnwindParams {
        address lendingAdapter; // Address of the lending adapter to repay the debt
        address flashAdapter; // Address of the flash loan adapter to cover the debt
        address lendingPool; // Address of the pool where the position is open
        address collateralToken; // Collateral token to be withdrawn (e.g., WBTC)
        address debtToken; // Debt token to be repaid (e.g., USDC)
        address user; // Address of the user's specific Beacon Proxy
        uint256 slippageBps; // Buffer for swap slippage in basis points (e.g., 100 = 1%)
    }

    constructor(address _oracle) {
        ORACLE = LederoOracle(_oracle);
    }

    function calculateOpenParams(QuoteOpenParams calldata params)
        external
        view
        returns (uint256 flashLoanAmount, uint256 borrowAmount, uint256 totalRepayAmount)
    {
        // Calculate flash amount, using collateral amount and leverage
        flashLoanAmount = LeverageMath.calcFlashLoanAmount(params.collateralAmount, params.desiredLeverage);
        uint256 totalCollateral = params.collateralAmount + flashLoanAmount;

        // Get LTV from lending adapter
        uint256 ltv = ILendingAdapter(params.lendingAdapter).getLtv(params.lendingPool, params.collateralToken);

        // Prices
        uint256 colPrice =
            params.collateralTokenPrice > 0 ? params.collateralTokenPrice : ORACLE.getPrice(params.collateralToken);

        uint256 borrowPrice =
            params.borrowTokenPrice > 0 ? params.borrowTokenPrice : ORACLE.getPrice(params.borrowToken);

        uint8 colDec = _getDecimals(params.collateralToken);
        uint8 borrowDec = _getDecimals(params.borrowToken);

        // Apply safety cocoefficient
        borrowAmount = LeverageMath.calcSafeBorrowAmount(totalCollateral, ltv, colPrice, borrowPrice, colDec, borrowDec);

        // Calculate full repay amount = amount + flash loan fee
        totalRepayAmount =
            IFlashLoanAdapter(params.flashAdapter).getFullRepayAmount(params.collateralToken, flashLoanAmount);
    }

    function calculateUnwindParams(QuoteUnwindParams calldata params)
        external
        view
        returns (uint256 collateralToWithdraw, uint256 debtToRepay, uint256 totalFlashRepay)
    {
        debtToRepay =
            ILendingAdapter(params.lendingAdapter).getDebtAmount(params.lendingPool, params.user, params.debtToken);

        if (debtToRepay == 0) return (0, 0, 0);

        uint256 colPrice = ORACLE.getPrice(params.collateralToken);
        uint256 debtPrice = ORACLE.getPrice(params.debtToken);

        uint8 colDec = _getDecimals(params.collateralToken);
        uint8 debtDec = _getDecimals(params.debtToken);

        // How much collateral we should withdraw + slippage
        collateralToWithdraw = LeverageMath.calcCollateralToWithdraw(
            debtToRepay, colPrice, debtPrice, colDec, debtDec, params.slippageBps
        );

        totalFlashRepay = IFlashLoanAdapter(params.flashAdapter).getFullRepayAmount(params.debtToken, debtToRepay);
    }

    function getMaxLeverage(address lendingAdapter, address lendingPool, address collateralToken)
        external
        view
        returns (uint256)
    {
        uint256 ltv = ILendingAdapter(lendingAdapter).getLtv(lendingPool, collateralToken);
        return LeverageMath.calcMaxLeverage(ltv);
    }

    function _getDecimals(address token) internal view returns (uint8) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("decimals()"));
        if (!success) revert NoDecimals();
        return abi.decode(data, (uint8));
    }
}
