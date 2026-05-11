pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";

contract Mock1InchRouter is Test {
    error MockSwapFailed();

    function swap(address tokenIn, address tokenOut, uint256 amountOut, address receiver) external payable {
        uint256 allowance = IERC20(tokenIn).allowance(msg.sender, address(this));
        IERC20(tokenIn).transferFrom(msg.sender, address(this), allowance);
        IERC20(tokenOut).transfer(receiver, amountOut);
    }
}
