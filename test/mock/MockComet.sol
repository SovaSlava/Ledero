// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockComet {
    using SafeERC20 for IERC20;

    function supply(address asset, uint256 amount) external {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    }

    function borrowBalanceOf(address) external pure returns (uint256) {
        return 1 ether;
    }

    function withdraw(address borrowToken, uint256 borrowAmount) external {
        IERC20(borrowToken).safeTransfer(msg.sender, borrowAmount);
    }
}
