// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockAaveRewardsController {
    using SafeERC20 for IERC20;

    address public rewardToken;

    constructor(address _rewardToken) {
        rewardToken = _rewardToken;
    }

    function claimAllRewards(
        address[] calldata, /*assets*/
        address to
    )
        external
        returns (address[] memory, uint256[] memory)
    {
        uint256 rewardAmount = 50e18;

        IERC20(rewardToken).safeTransfer(to, rewardAmount);

        address[] memory rewardsList = new address[](1);
        rewardsList[0] = rewardToken;

        uint256[] memory claimedAmounts = new uint256[](1);
        claimedAmounts[0] = rewardAmount;

        return (rewardsList, claimedAmounts);
    }
}
