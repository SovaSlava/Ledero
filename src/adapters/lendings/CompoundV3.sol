// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {ILendingAdapter} from "../../interfaces/internal/ILendingAdapter.sol";
import {IComet} from "../../interfaces/external/ICompound.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ICometRewards {
    function claimTo(address comet, address src, address to, bool shouldAccrue) external;
}

contract CompoundV3Adapter is ILendingAdapter {
    using SafeERC20 for IERC20;

    function supplyAndBorrow(
        address pool,
        address collateralToken,
        uint256 collateralAmount,
        address borrowToken,
        uint256 borrowAmount
    ) external override {
        if (collateralAmount > 0) {
            IERC20(collateralToken).forceApprove(pool, collateralAmount);
            IComet(pool).supply(collateralToken, collateralAmount);
        }
        if (borrowAmount > 0) {
            IComet(pool).withdraw(borrowToken, borrowAmount);
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
            IComet(pool).supply(debtToken, debtAmount);
        }
        if (collateralToWithdraw > 0) {
            IComet(pool).withdraw(collateralToken, collateralToWithdraw);
        }
    }

    function getDebtAmount(address pool, address user, address) external view override returns (uint256) {
        return IComet(pool).borrowBalanceOf(user);
    }

    function getLTV(address pool, address collateralToken) external view override returns (uint256) {
        IComet.AssetInfo memory assetInfo = IComet(pool).getAssetInfoByAddress(collateralToken);
        // LTV * BPS / WAD
        return (uint256(assetInfo.borrowCollateralFactor) * 10000) / 1e18;
    }

    /**
     * @dev Compound allow claim all tokens in pool and do not specify them
     */
    function claimRewards(
        address pool,
        address,
        /* collateralToken */
        address,
        /* debtToken */
        address rewardContract,
        address to
    )
        external
        override
    {
        // shouldAccrue = true (recalculate rewards)
        ICometRewards(rewardContract).claimTo(pool, address(this), to, true);
    }

    function getPositionHealthFactor(address pool, address user, address collateralAsset)
        external
        view
        returns (uint256 health)
    {
        IComet comet = IComet(pool);
        uint256 borrowAmount = comet.borrowBalanceOf(user);
        if (borrowAmount == 0) return type(uint256).max; 

        address basePriceFeed = comet.baseTokenPriceFeed();
        uint256 borrowPrice = comet.getPrice(basePriceFeed);
        uint256 baseScale = comet.baseScale(); 
        // Debt in USD
        uint256 debtValueUSD = (borrowAmount * borrowPrice) / baseScale;
        if (debtValueUSD == 0 || debtValueUSD < 1000) return type(uint256).max;

        uint256 colBalance = comet.collateralBalanceOf(user, collateralAsset);
        IComet.AssetInfo memory assetInfo = comet.getAssetInfoByAddress(collateralAsset);
        uint256 colPrice = comet.getPrice(assetInfo.priceFeed);
        // Collateral in USD
        uint256 colValueUSD = (colBalance * colPrice) / assetInfo.scale;
        // Max debt in USD = Collateral in USD * LT
        uint256 maxDebtCapacityUSD = (colValueUSD * assetInfo.liquidateCollateralFactor) / 1e18;

        return (maxDebtCapacityUSD * 1e18) / debtValueUSD;
    }

    function getVersion() external pure returns (uint256) {
        return 1;
    }
}
