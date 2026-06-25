// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;
import {AdapterAction} from "./ILederoTypes.sol";

interface IFlashLoanAdapter {
    function takeFundsFirstStep(address token, uint256 amount, bytes calldata userData)
        external
        view
        returns (AdapterAction[] memory action);

    function takeFundsSecondStep(address token, uint256 amount) external view returns (AdapterAction[] memory actions);

    function getFullRepayAmount(address token, uint256 amount) external view returns (uint256 totalRepay);

    function repayFunds(address token, uint256 amountToRepay) external view returns (AdapterAction[] memory actions);

    function VAULT() external view returns (address);
}
