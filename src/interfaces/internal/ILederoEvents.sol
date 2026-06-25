// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

/**
 * @title IStrataxEvents
 * @notice All events
 */
interface ILederoEvents {
    /**
     * @param protocol address of lending adapter
     * @param collateralToken collatral
     * @param borrowToken borrow token
     * @param totalCollateral own funds + flash loan amount
     * @param borrowAmount borrowed amount
     */
    event LeveragePositionCreated(
        address indexed protocol,
        uint256 indexed totalCollateral,
        uint256 indexed borrowAmount,
        address collateralToken,
        address borrowToken
    );

    /**
     * @param protocol address of lending adapter
     * @param collateralToken collateral
     * @param debtToken debt token
     * @param withdrawnAmount withdrawn collateral amount
     */
    event LeveragePositionUnwound(
        address indexed protocol, address indexed debtToken, uint256 indexed withdrawnAmount, address collateralToken
    );

    /**
     * @param lendginAdapterFrom Adapter from
     * @param lendginAdapterTo Adapter to
     * @param collateralToken collateral token
     * @param debtToken debt token
     */
    event PositionMigrated(
        address indexed lendginAdapterFrom,
        address indexed lendginAdapterTo,
        address indexed collateralToken,
        address debtToken
    );

    /**
     * @notice Manual collateral added
     */
    event CollateralAdded(address indexed admin, address indexed token, uint256 indexed amount);

    /**
     * @notice Manual debt repaid
     */
    event DebtRepaid(address indexed admin, address indexed token, uint256 indexed amount);
}
