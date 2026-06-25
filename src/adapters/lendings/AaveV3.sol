// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {ILendingAdapter} from "../../interfaces/internal/ILendingAdapter.sol";
import {IAaveV3Pool} from "../../interfaces/external/IAaveV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AdapterAction} from "../../interfaces/internal/ILederoTypes.sol";

interface IRewardsController {
    function claimAllRewards(address[] calldata assets, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}

contract AaveV3Adapter is ILendingAdapter {
    function supplyAndBorrow(
        address pool,
        address collateralToken,
        uint256 collateralAmount,
        address borrowToken,
        uint256 borrowAmount
    ) external view override returns (AdapterAction[] memory actions) {
        actions = new AdapterAction[](2);

        uint256 currentIndex;

        // Supply
        if (collateralAmount > 0) {
            actions[currentIndex] = AdapterAction({
                target: pool,
                approveToken: collateralToken,
                approveAmount: collateralAmount,
                callData: abi.encodeWithSelector(
                    IAaveV3Pool.supply.selector, collateralToken, collateralAmount, msg.sender, 0
                )
            });
            unchecked {
                ++currentIndex;
            }
        }

        // Borrow
        if (borrowAmount > 0) {
            actions[currentIndex] = AdapterAction({
                target: pool,
                approveToken: address(0),
                approveAmount: 0,
                callData: abi.encodeWithSelector(
                    IAaveV3Pool.borrow.selector,
                    borrowToken,
                    borrowAmount,
                    2, // 2 - Variable Rate
                    0,
                    msg.sender
                )
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
    ) external view override returns (AdapterAction[] memory actions) {
        actions = new AdapterAction[](2);

        uint256 currentIndex;

        // Repay
        if (debtAmount > 0) {
            actions[currentIndex] = AdapterAction({
                target: pool,
                approveToken: debtToken,
                approveAmount: debtAmount,
                callData: abi.encodeWithSelector(IAaveV3Pool.repay.selector, debtToken, debtAmount, 2, msg.sender)
            });
            unchecked {
                ++currentIndex;
            }
        }

        // Withdraw
        if (collateralToWithdraw > 0) {
            actions[currentIndex] = AdapterAction({
                target: pool,
                approveToken: address(0),
                approveAmount: 0,
                callData: abi.encodeWithSelector(
                    IAaveV3Pool.withdraw.selector, collateralToken, collateralToWithdraw, msg.sender
                )
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

    function getDebtAmount(address pool, address user, address debtToken) external view returns (uint256) {
        IAaveV3Pool.ReserveData memory reserve = IAaveV3Pool(pool).getReserveData(debtToken);
        return IERC20(reserve.variableDebtTokenAddress).balanceOf(user);
    }

    function getLtv(address pool, address collateralToken) external view returns (uint256) {
        return IAaveV3Pool(pool).getConfiguration(collateralToken).data & 0xFFFF;
    }

    function claimRewards(address pool, address collateralToken, address debtToken, address rewardContract, address to)
        external
        view
        returns (AdapterAction[] memory actions)
    {
        actions = new AdapterAction[](1);
        IAaveV3Pool.ReserveData memory colReserve = IAaveV3Pool(pool).getReserveData(collateralToken);
        IAaveV3Pool.ReserveData memory debtReserve = IAaveV3Pool(pool).getReserveData(debtToken);

        address[] memory assets = new address[](2);
        assets[0] = colReserve.aTokenAddress;
        assets[1] = debtReserve.variableDebtTokenAddress;

        actions[0] = AdapterAction({
            target: rewardContract,
            approveToken: address(0),
            approveAmount: 0,
            callData: abi.encodeWithSelector(IRewardsController.claimAllRewards.selector, assets, to)
        });
    }

    function getPositionHealthFactor(address pool, address user, address) external view override returns (uint256) {
        (,,,,, uint256 healthFactor) = IAaveV3Pool(pool).getUserAccountData(user);
        return healthFactor;
    }

    function getVersion() external pure returns (uint256) {
        return 1;
    }
}
