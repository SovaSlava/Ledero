// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

interface IFlashLoanAdapter {
    // amount + fee
    function getFullRepayAmount(address token, uint256 amount) external view returns (uint256);

    function executeFlashLoan(address token, uint256 amount) external;

    function repayFunds(address token, uint256 amount) external;
}
