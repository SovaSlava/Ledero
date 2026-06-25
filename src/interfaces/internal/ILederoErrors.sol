// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

interface ILederoErrors {
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
    error ActionExecutionFailed();
    error InvalidlendingPool();
    error CompoundlendingPoolRequired();
    error InvalidAdapterPrefix();
    error InvalidFlashLoanFee(uint256 providedFee);
    error ExpiredDeadline();
    error InsufficientCollateralRecovered(uint256 minCollateralToSupply, uint256 amountToSupply);

    // Finance checks
    error InsufficientSwapReturn(uint256 expected, uint256 actual);
    error InsufficientSwapReturnForFlashLoan(uint256 expected, uint256 actual);
    error UnwindSwapReturnTooLow(uint256 expected, uint256 actual);
    error PositionHealthTooLow();
    error MigratedPositionHealthTooLow();

    // Oracle
    error IncorrectLength();
    error UnsupportDecimals();
    error PriceFeedNotSet();
    error HeartbeatNotSet();
    error InvalidPrice();
    error RoundIncomplete();
    error StaleRound();
    error StalePrice();
    event PriceFeedUpdated(address indexed token, address indexed priceFeed, uint256 indexed heartbeat);

    // Quouter
    error NoDecimals();
}
