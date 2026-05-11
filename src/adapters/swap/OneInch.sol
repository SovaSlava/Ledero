// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract OneInchAdapter {
    using SafeERC20 for IERC20;

    address public immutable ROUTER;
    address public immutable LEDERO;

    error SwapFailed();
    error InsufficientReturnAmount(uint256 expected, uint256 actual);
    error OnlyLedero();
    error InsufficientInput();

    constructor(address _router, address _ledero) {
        ROUTER = _router;
        LEDERO = _ledero;
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, bytes calldata payload)
        external
        returns (uint256 returnAmount)
    {
        require(msg.sender == LEDERO, OnlyLedero());
        uint256 currentIn = IERC20(tokenIn).balanceOf(address(this));
        if (currentIn < amountIn) revert InsufficientInput();

        IERC20(tokenIn).forceApprove(ROUTER, amountIn);

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(LEDERO);

        (bool success,) = ROUTER.call(payload);
        require(success, SwapFailed());

        uint256 balanceAfter = IERC20(tokenOut).balanceOf(LEDERO);
        returnAmount = balanceAfter - balanceBefore;

        require(returnAmount >= minAmountOut, InsufficientReturnAmount(minAmountOut, returnAmount));

        // return remain tokenIn
        uint256 leftIn = IERC20(tokenIn).balanceOf(address(this));
        if (leftIn > 0) {
            IERC20(tokenIn).safeTransfer(LEDERO, leftIn);
        }

        IERC20(tokenIn).forceApprove(ROUTER, 0);
    }

    function getVersion() external pure returns (uint256) {
        return 1;
    }
}
