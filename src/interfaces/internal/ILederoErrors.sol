// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

// Access errors
error UnsupportedProtocol();
error UnauthorizedCallbackCaller();
error UnknownOperation();
error UnauthorizedCallback();

// Adapter's errors
error AdapterExecutionFailed(bytes reason);
error OneInchSwapFailed();
error OnlyFlashAdapter();
// Validate input data

error ZeroAddress();
error ZeroCollateralAmount();
error ZeroFlashLoanAmount();
error ZeroDebtAmount();
error ZeroCollateralToWithdraw();
error ZeroDebtToRepay();
error ZeroDebtToMigrate();
error AdapterAddressZero();
error InvalidlendingPool();
error CompoundlendingPoolRequired();
error InvalidAdapterPrefix();
error InvalidFlashLoanFee(uint256 providedFee);
error InvalidVanityAddress();
error ExpiredDeadline();
error InsufficientCollateralRecovered(uint256 minCollateralToSupply, uint256 amountToSupply);

// Finance checks
error InsufficientSwapReturn(uint256 expected, uint256 actual);
error InsufficientSwapReturnForFlashLoan(uint256 expected, uint256 actual);
error UnwindSwapReturnTooLow(uint256 expected, uint256 actual);
error PositionHealthTooLow();
error MigratedPositionHealthTooLow();

