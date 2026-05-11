// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import "./internal/ILederoTypes.sol";
import "./internal/ILederoErrors.sol";
import "./internal/ILederoEvents.sol";
import "./internal/IConstants.sol";

interface ILedero is ILederoEvents {
    function initialize() external;

    function unwindPosition(UnwindPositionParams calldata params) external;

    function recoverTokens(address _token, uint256 _amount) external;

    function createLeveragedPosition(OpenPositionParams calldata params) external;

    function receiveFlashLoan() external;
}
