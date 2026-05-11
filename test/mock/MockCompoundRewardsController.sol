// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockCompoundRewardsController {
    using SafeERC20 for IERC20;

    address public rewardToken;

    constructor(address _rewardToken) {
        rewardToken = _rewardToken;
    }

    function claimTo(address comet, address src, address to, bool shouldAccrue) external {
        comet;
        src;
        shouldAccrue;

        uint256 rewardAmount = 30 * 10 ** 18;

        IERC20(rewardToken).safeTransfer(to, rewardAmount);
    }
}
