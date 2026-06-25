pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Mock1InchRouter {
    using SafeERC20 for IERC20;
    error MockSwapFailed();

    function swap(address tokenIn, address tokenOut, uint256 amountOut, address receiver) external payable {
        uint256 allowance = IERC20(tokenIn).allowance(msg.sender, address(this));
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), allowance);
        IERC20(tokenOut).safeTransfer(receiver, amountOut);
    }
}
