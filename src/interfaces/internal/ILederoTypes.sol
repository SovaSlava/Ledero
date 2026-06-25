// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

enum Operation {
    NONE,
    OPEN_POSITION,
    UNWIND_POSITION,
    MIGRATE_POSITION
}

/**
 * @notice Parameters for open a leveraged position.
 * @dev Passed from the frontend into the main Ledero contract.
 * @param lendingPool Lending liquidity pool
 * @param collateralAmount Initial amount provided by the user from their own wallet.
 * @param collateralToken Address of the token being used as collateral.
 * @param borrowAmount Exact amount to borrow from the lending protocol to repay the flash loan.
 * @param borrowToken Address of the token being borrowed.
 * @param flashLoanAmount Amount of `borrowToken` to request via the flash loan provider to build leverage.
 * @param lendingAdapter Address of the Ledero adapter for the specific lending protocol.
 * @param minReturnAmount Minimum acceptable amount of `collateralToken` to receive from the swap (slippage protection).
 * @param flashAdapter Address of the flashloan adapter handling the flash loan logic.
 * @param swapAdapter Address of the swap adapter handling the DEX aggregation (e.g., OneInchAdapter).
 * @param deadline Timestamp after which the transaction will revert, protecting against delayed execution.
 * @param swapData Encoded payload provided by the swap aggregator API to execute the swap.
 */
struct OpenPositionParams {
    address lendingPool;
    uint256 collateralAmount;
    address collateralToken;
    uint256 borrowAmount;
    address borrowToken;
    uint256 flashLoanAmount;
    address lendingAdapter;
    uint256 minReturnAmount;
    address flashAdapter;
    address swapAdapter;
    uint256 deadline;
    bytes swapData;
}

/**
 * @notice Parameters for close (unwind) a leveraged position.
 * @param lendingPool Lending liquidity pool where the position is currently open.
 * @param collateralToWithdraw Amount of collateral to withdraw from the lending pool after the debt is repaid.
 * @param collateralToken Address of the collateral token being withdrawn.
 * @param debtToRepay Exact amount of debt to flash-borrow and repay to the lending protocol.
 * @param debtToken Address of the token being repaid.
 * @param minReturnAmount The minimum acceptable amount of `debtToken` to receive from the swap.
 * @param lendingAdapter Address of the Ledero adapter for the specific lending protocol .
 * @param flashAdapter Address of the Ledero adapter handling the flash loan.
 * @param swapAdapter Address of the Ledero adapter handling the swap aggregation.
 * @param deadline Timestamp after which the transaction will revert, protecting the user from delayed execution and worse prices.
 * @param swapData: Encoded payload provided by the swap aggregator API.
 */
struct UnwindPositionParams {
    address lendingPool;
    uint256 collateralToWithdraw;
    address collateralToken;
    uint256 debtToRepay;
    address debtToken;
    uint256 minReturnAmount;
    address lendingAdapter;
    address flashAdapter;
    address swapAdapter;
    uint256 deadline;
    bytes swapData;
}

/**
 * @param collateralToken Address of the collateral token being withdrawn.
 * @param collateralAmount Amount of collateral to withdraw from the source pool and migrate.
 * @param debtToken Address of the token currently borrowed.
 * @param debtAmount Amount of debt to flash-borrow to clear the position in the source pool.
 * @param fromPool Address of the source lending liquidity pool where the position is currently held.
 * @param minCollateralToSupply Minimum acceptable amount of collateral to supply to the new pool.
 * @param toPool Address of the destination lending liquidity pool to migrate the position to.
 * @param lendingAdapterFrom Address of the lending adapter handling the source protocol.
 * @param lendingAdapterTo Address of the lending adapter handling the destination protocol.
 * @param flashAdapter Address of the flashloan adapter handling the flash loan execution.
 * @param deadline Timestamp after which the transaction will revert, protecting the user from delayed execution.
 */
struct MigrationParams {
    address collateralToken;
    uint256 collateralAmount;
    address debtToken;
    uint256 debtAmount;
    address fromPool;
    uint256 minCollateralToSupply;
    address toPool;
    address lendingAdapterFrom;
    address lendingAdapterTo;
    address flashAdapter;
    uint256 deadline;
}

/**
 * @param target Address of the smart contract to which the low-level `call` will be made.
 * @param approveToken Address of the token that requires approval before the call. If set to address(0), this step is skipped.
 * @param approveAmount Token amount to approve.
 * @param callData The encoded call data (selector + ABI-encoded parameters).
 */
struct AdapterAction {
    address target;
    address approveToken;
    uint256 approveAmount;
    bytes callData;
}
