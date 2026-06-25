// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;
import {AdapterAction} from "../../interfaces/internal/ILederoTypes.sol";

interface ISwapAdapter {
    function swap(address tokenIn, uint256 amountIn, bytes calldata payload)
        external
        view
        returns (AdapterAction[] memory actions);
}
