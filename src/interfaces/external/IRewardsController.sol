// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

interface IRewardsController {
    /**
     * @notice Claims all rewards for a list of assets
     * @param assets The list of aTokens to check for rewards
     * @param to The address where the claimed rewards will be sent
     * @return rewardsList Array of addresses of the reward tokens claimed
     * @return claimedAmounts Array of the amounts of each reward token claimed
     */
    function claimAllRewards(address[] calldata assets, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}
