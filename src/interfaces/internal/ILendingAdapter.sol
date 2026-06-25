// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;
import {AdapterAction} from "../../interfaces/internal/ILederoTypes.sol";

/**
 * @title ILendingAdapter
 */
interface ILendingAdapter {
    function supplyAndBorrow(
        address pool,
        address collateralToken,
        uint256 collateralAmount,
        address borrowToken,
        uint256 borrowAmount
    ) external view returns (AdapterAction[] memory actions);

    function repayAndWithdraw(
        address pool,
        address collateralToken,
        uint256 collateralToWithdraw,
        address debtToken,
        uint256 debtAmount
    ) external view returns (AdapterAction[] memory actions);

    function getDebtAmount(address pool, address user, address debtToken) external view returns (uint256);

    function getLtv(address pool, address collateralToken) external view returns (uint256);

    /**
     * @notice claim incentive rewards
     * @param pool pool address
     * @param collateralToken collateral token
     * @param debtToken debt token
     * @param rewardContract reward contract controller
     * @param to send to
     */
    function claimRewards(address pool, address collateralToken, address debtToken, address rewardContract, address to)
        external
        view
        returns (AdapterAction[] memory actions);

    function getPositionHealthFactor(address pool, address user, address collateralAsset)
        external
        view
        returns (uint256);

    function getVersion() external pure returns (uint256);
}
