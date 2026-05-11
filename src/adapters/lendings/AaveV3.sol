// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {ILendingAdapter} from "../../interfaces/internal/ILendingAdapter.sol";
import {IAaveV3Pool} from "../../interfaces/external/IAaveV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; // ДОБАВИЛИ

interface IRewardsController {
    function claimAllRewards(address[] calldata assets, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}

contract AaveV3Adapter is ILendingAdapter {
    using SafeERC20 for IERC20;

    function supplyAndBorrow(
        address pool,
        address collateralToken,
        uint256 collateralAmount,
        address borrowToken,
        uint256 borrowAmount
    ) external override {
        if (collateralAmount > 0) {
            // forceApprove - for usdt. 0 -> amount
            IERC20(collateralToken).forceApprove(pool, collateralAmount);
            IAaveV3Pool(pool).supply(collateralToken, collateralAmount, address(this), 0);
        }
        if (borrowAmount > 0) {
            // 2 - Variable Rate
            IAaveV3Pool(pool).borrow(borrowToken, borrowAmount, 2, 0, address(this));
        }
    }

    function repayAndWithdraw(
        address pool,
        address collateralToken,
        uint256 collateralToWithdraw,
        address debtToken,
        uint256 debtAmount
    ) external override {
        if (debtAmount > 0) {
            IERC20(debtToken).forceApprove(pool, debtAmount);
            IAaveV3Pool(pool).repay(debtToken, debtAmount, 2, address(this));
        }
        if (collateralToWithdraw > 0) {
            IAaveV3Pool(pool).withdraw(collateralToken, collateralToWithdraw, address(this));
        }
    }

    function getDebtAmount(address pool, address user, address debtToken) external view returns (uint256) {
        IAaveV3Pool.ReserveData memory reserve = IAaveV3Pool(pool).getReserveData(debtToken);
        return IERC20(reserve.variableDebtTokenAddress).balanceOf(user);
    }

    function getLTV(address pool, address collateralToken) external view returns (uint256) {
        return IAaveV3Pool(pool).getConfiguration(collateralToken).data & 0xFFFF;
    }

    function claimRewards(address pool, address collateralToken, address debtToken, address rewardContract, address to)
        external
    {
        IAaveV3Pool.ReserveData memory colReserve = IAaveV3Pool(pool).getReserveData(collateralToken);
        IAaveV3Pool.ReserveData memory debtReserve = IAaveV3Pool(pool).getReserveData(debtToken);

        address[] memory assets = new address[](2);
        assets[0] = colReserve.aTokenAddress;
        assets[1] = debtReserve.variableDebtTokenAddress;

        IRewardsController(rewardContract).claimAllRewards(assets, to);
    }

    function getPositionHealthFactor(address pool, address user, address) external view override returns (uint256) {
        (,,,,, uint256 healthFactor) = IAaveV3Pool(pool).getUserAccountData(user);
        return healthFactor;
    }

    function getVersion() external pure returns (uint256) {
        return 1;
    }
}
