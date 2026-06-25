// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {ILederoErrors} from "./internal/ILederoErrors.sol";
import {ILederoEvents} from "./internal/ILederoEvents.sol";
import {OpenPositionParams, UnwindPositionParams} from "./internal/ILederoTypes.sol";

interface ILedero is ILederoEvents, ILederoErrors {
    function initialize() external;

    function unwindPosition(UnwindPositionParams calldata params) external payable;

    function recoverTokens(address _token, uint256 _amount) external payable;

    function createLeveragedPosition(OpenPositionParams calldata params) external payable;

    function receiveFlashLoan(bytes calldata params) external payable;
}
