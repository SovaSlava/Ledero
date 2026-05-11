// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

interface ISwapAdapter {
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, bytes calldata payload)
        external
        returns (uint256 returnAmount);
}
