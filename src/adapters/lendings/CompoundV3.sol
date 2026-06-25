// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {ILendingAdapter} from "../../interfaces/internal/ILendingAdapter.sol";
import {IComet} from "../../interfaces/external/ICompound.sol";
import {AdapterAction} from "../../interfaces/internal/ILederoTypes.sol";

interface ICometRewards {
    function claimTo(address comet, address src, address to, bool shouldAccrue) external;
}

contract CompoundV3Adapter is ILendingAdapter {
    function supplyAndBorrow(
        address pool,
        address collateralToken,
        uint256 collateralAmount,
        address borrowToken,
        uint256 borrowAmount
    ) external pure override returns (AdapterAction[] memory actions) {
        actions = new AdapterAction[](2);

        uint256 currentIndex;

        if (collateralAmount > 0) {
            actions[currentIndex] = AdapterAction({
                target: pool,
                approveToken: collateralToken,
                approveAmount: collateralAmount,
                callData: abi.encodeWithSelector(IComet.supply.selector, collateralToken, collateralAmount)
            });
            unchecked {
                ++currentIndex;
            }
        }
        if (borrowAmount > 0) {
            actions[currentIndex] = AdapterAction({
                target: pool,
                approveToken: address(0),
                approveAmount: 0,
                callData: abi.encodeWithSelector(IComet.withdraw.selector, borrowToken, borrowAmount)
            });
            unchecked {
                ++currentIndex;
            }
        }

        if (currentIndex < 2) {
            assembly ("memory-safe") {
                mstore(actions, currentIndex)
            }
        }
    }

    function repayAndWithdraw(
        address pool,
        address collateralToken,
        uint256 collateralToWithdraw,
        address debtToken,
        uint256 debtAmount
    ) external pure override returns (AdapterAction[] memory actions) {
        actions = new AdapterAction[](2);

        uint256 currentIndex;

        if (debtAmount > 0) {
            actions[currentIndex] = AdapterAction({
                target: pool,
                approveToken: debtToken,
                approveAmount: debtAmount,
                callData: abi.encodeWithSelector(IComet.supply.selector, debtToken, debtAmount)
            });
            unchecked {
                ++currentIndex;
            }
        }
        if (collateralToWithdraw > 0) {
            actions[currentIndex] = AdapterAction({
                target: pool,
                approveToken: address(0),
                approveAmount: 0,
                callData: abi.encodeWithSelector(IComet.withdraw.selector, collateralToken, collateralToWithdraw)
            });
            unchecked {
                ++currentIndex;
            }
        }
        if (currentIndex < 2) {
            assembly ("memory-safe") {
                mstore(actions, currentIndex)
            }
        }
    }

    function getDebtAmount(address pool, address user, address) external view override returns (uint256) {
        return IComet(pool).borrowBalanceOf(user);
    }

    /**
     * @dev LTV * BPS / 1e18
     * LTV * 10000 / 1e18
     * LTV * 1 / 1e14
     * LTV / 1e14
     */
    function getLtv(address pool, address collateralToken) external view override returns (uint256) {
        IComet.AssetInfo memory assetInfo = IComet(pool).getAssetInfoByAddress(collateralToken);
        return uint256(assetInfo.borrowCollateralFactor) / 1e14;
    }

    /// @dev https://docs.compound.finance/protocol-rewards/
    function claimRewards(
        address comet,
        address, // collateralToken
        address, // debtToken
        address rewardContract,
        address to
    )
        external
        view
        returns (AdapterAction[] memory actions)
    {
        actions = new AdapterAction[](1);
        // shouldAccrue = true (recalculate rewards)
        actions[0] = AdapterAction({
            target: rewardContract,
            approveToken: address(0),
            approveAmount: 0,
            callData: abi.encodeWithSelector(ICometRewards.claimTo.selector, comet, msg.sender, to, true)
        });
    }

    /**
     * @notice Compound doesn't have function for calculating health factor.
     * @dev We use formula: HF = ColUSD_Discounted / DebtUSD
     *
     * Raw Formula:
     * ColUSD_Discounted = (colBalance * colPrice / colScale) * (liquidateCollateralFactor / 1e18)
     * DebtUSDValue = (borrowBalance * borrowPrice / baseScale)
     *
     * To prevent precision loss from multiple solidity truncations (divisions)
     * we reduce formula to a single division:
     * HF_NEW = (colBalance * colPrice * liquidateCollateralFactor * baseScale) /
     * (borrowBalance * borrowPrice * colScale)
     */
    function getPositionHealthFactor(address pool, address user, address collateralAsset)
        external
        view
        returns (uint256 health)
    {
        IComet comet = IComet(pool);
        uint256 borrowAmount = comet.borrowBalanceOf(user);
        if (borrowAmount == 0) return type(uint256).max;

        uint256 colBalance = comet.collateralBalanceOf(user, collateralAsset);

        IComet.AssetInfo memory assetInfo = comet.getAssetInfoByAddress(collateralAsset);

        uint256 borrowPrice = comet.getPrice(comet.baseTokenPriceFeed());
        uint256 colPrice = comet.getPrice(assetInfo.priceFeed);

        uint256 numerator = colBalance * colPrice * assetInfo.liquidateCollateralFactor * comet.baseScale();
        uint256 denominator = borrowAmount * borrowPrice * assetInfo.scale;

        return numerator / denominator;
    }

    function getVersion() external pure returns (uint256) {
        return 1;
    }
}
