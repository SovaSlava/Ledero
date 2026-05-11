// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {LeverageMath} from "./libraries/LeverageMath.sol";
import {TransientBytes} from "./libraries/TransientBytes.sol";
import {ILendingAdapter} from "./interfaces/internal/ILendingAdapter.sol";
import {IFlashLoanAdapter} from "./interfaces/internal/IFlashLoanAdapter.sol";
import {ISwapAdapter} from "./interfaces/internal/ISwapAdapter.sol";
import "./interfaces/ILedero.sol";

contract Ledero is ILedero, Initializable, Ownable2StepUpgradeable {
    using LeverageMath for uint256;
    using SafeERC20 for IERC20;

    address transient _expectedFlashAdapter;
    Operation transient _currentOperation;

    modifier deadlineCheck(uint256 deadline) {
        require(block.timestamp <= deadline, ExpiredDeadline());
        _;
    }

    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __Ownable2Step_init();
    }

    /**
     * @notice Opens a leveraged position using flash loans and cross-protocol liquidity.
     * @param params Struct OpenPositionParams has fields:
     * - lendingPool: Lending liquidity pool.
     * - collateralAmount: Initial amount provided by the user from their own wallet.
     * - collateralToken: Address of the token being used as collateral.
     * - borrowAmount: Exact amount to borrow from the lending protocol to repay the flash loan.
     * - borrowToken: Address of the token being borrowed.
     * - flashLoanAmount: Amount of `borrowToken` to request via the flash loan provider to build leverage.
     * - lendingAdapter: Address of the Ledero adapter for the specific lending protocol.
     * - minReturnAmount: Minimum acceptable amount of `collateralToken` to receive from the swap (slippage protection).
     * - flashAdapter: Address of the flashloan adapter handling the flash loan logic.
     * - swapAdapter: Address of the swap adapter handling the DEX aggregation (e.g., OneInchAdapter).
     * - deadline: Timestamp after which the transaction will revert, protecting against delayed execution.
     * - swapData: Encoded payload provided by the swap aggregator API to execute the swap.
     */
    function createLeveragedPosition(OpenPositionParams calldata params)
        external
        onlyOwner
        deadlineCheck(params.deadline)
    {
        _validateAdapter(params.lendingAdapter, LENDING_PREFIX);
        _validateAdapter(params.flashAdapter, FLASH_PREFIX);
        _validateAdapter(params.swapAdapter, SWAP_PREFIX);

        TransientBytes.tstore(_PARAMS_SLOT, abi.encode(params));
        _expectedFlashAdapter = params.flashAdapter;
        _currentOperation = Operation.OPEN_POSITION;

        // Transfer initial amount from user
        IERC20(params.collateralToken).safeTransferFrom(msg.sender, address(this), params.collateralAmount);

        IFlashLoanAdapter(params.flashAdapter).executeFlashLoan(params.collateralToken, params.flashLoanAmount);

        _expectedFlashAdapter = address(0);
    }

    function _executeOpenPosition(OpenPositionParams memory params) internal {
        // Amount = initial amount + flashloan amount
        uint256 totalCollateral = params.collateralAmount + params.flashLoanAmount;

        // Supply to lendgin and borrow
        (bool successOpen, bytes memory reason) = params.lendingAdapter
            .delegatecall(
                abi.encodeWithSelector(
                    ILendingAdapter.supplyAndBorrow.selector,
                    params.lendingPool,
                    params.collateralToken,
                    totalCollateral,
                    params.borrowToken,
                    params.borrowAmount
                )
            );
        require(successOpen, AdapterExecutionFailed(reason));

        // Preparing swap
        IERC20(params.borrowToken).safeTransfer(params.swapAdapter, params.borrowAmount);

        // Swap borrow token to collateral
        uint256 returnAmount = ISwapAdapter(params.swapAdapter)
            .swap(
                params.borrowToken, params.collateralToken, params.borrowAmount, params.minReturnAmount, params.swapData
            );

        uint256 totalRepayAmount =
            IFlashLoanAdapter(msg.sender).getFullRepayAmount(params.collateralToken, params.flashLoanAmount);

        require(returnAmount >= totalRepayAmount, InsufficientSwapReturnForFlashLoan(totalRepayAmount, returnAmount));

        // Repay
        IERC20(params.collateralToken).forceApprove(msg.sender, totalRepayAmount);
        IFlashLoanAdapter(msg.sender).repayFunds(params.collateralToken, totalRepayAmount);

        // Supply remain tokens
        uint256 leftover = IERC20(params.collateralToken).balanceOf(address(this));
        if (leftover > 0) {
            (bool successDust, bytes memory reason) = params.lendingAdapter
                .delegatecall(
                    abi.encodeWithSelector(
                        ILendingAdapter.supplyAndBorrow.selector,
                        params.lendingPool,
                        params.collateralToken,
                        leftover,
                        address(0),
                        0
                    )
                );
            require(successDust, AdapterExecutionFailed(reason));
        }

        checkHF(params.collateralToken, params.lendingPool, params.lendingAdapter);

        emit LeveragePositionCreated(
            params.lendingAdapter,
            params.collateralToken,
            params.borrowToken,
            totalCollateral + leftover,
            params.borrowAmount
        );
    }

    /**
     * @notice Close a leveraged position using flash loan.
     * @param params Struct UnwindPositionParams has fields:
     * - lendingPool: Lending liquidity pool where the position is currently open.
     * - collateralToWithdraw: Amount of collateral to withdraw from the lending pool after the debt is repaid.
     * - collateralToken: Address of the collateral token being withdrawn.
     * - debtToRepay: Exact amount of debt to flash-borrow and repay to the lending protocol.
     * - debtToken: Address of the token being repaid.
     * - minReturnAmount: Minimum acceptable amount of `debtToken` to receive from the swap to ensure the flash loan can be repaid (slippage protection).
     * - lendingAdapter: Address of the Ledero adapter for the specific lending protocol .
     * - flashAdapter: Address of the Ledero adapter handling the flash loan.
     * - swapAdapter: Address of the Ledero adapter handling the swap aggregation.
     * - deadline: Timestamp after which the transaction will revert, protecting the user from delayed execution and worse prices.
     * - swapData: Encoded payload provided by the swap aggregator API.
     */
    function unwindPosition(UnwindPositionParams calldata params) external onlyOwner deadlineCheck(params.deadline) {
        _validateAdapter(params.lendingAdapter, LENDING_PREFIX);
        _validateAdapter(params.swapAdapter, SWAP_PREFIX);
        _validateAdapter(params.flashAdapter, FLASH_PREFIX);

        TransientBytes.tstore(_PARAMS_SLOT, abi.encode(params));
        _expectedFlashAdapter = params.flashAdapter;
        _currentOperation = Operation.UNWIND_POSITION;

        // Flashloan
        IFlashLoanAdapter(params.flashAdapter).executeFlashLoan(params.debtToken, params.debtToRepay);
        _expectedFlashAdapter = address(0);
    }

    function _executeUnwindPosition(UnwindPositionParams memory params) internal {
        // Amount + fee
        uint256 totalRepayAmount =
            IFlashLoanAdapter(msg.sender).getFullRepayAmount(params.debtToken, params.debtToRepay);

        // Repay and withdraw
        (bool successUnwind, bytes memory reason) = params.lendingAdapter
            .delegatecall(
                abi.encodeWithSelector(
                    ILendingAdapter.repayAndWithdraw.selector,
                    params.lendingPool,
                    params.collateralToken,
                    params.collateralToWithdraw,
                    params.debtToken,
                    params.debtToRepay
                )
            );
        require(successUnwind, AdapterExecutionFailed(reason));

        uint256 amountToSwap = params.collateralToWithdraw;
        if (amountToSwap == type(uint256).max) {
            amountToSwap = IERC20(params.collateralToken).balanceOf(address(this));
        }

        // Preparing swap
        IERC20(params.collateralToken).safeTransfer(params.swapAdapter, amountToSwap);

        // Swap collateral to debt token
        uint256 returnDebtToken = ISwapAdapter(params.swapAdapter)
            .swap(params.collateralToken, params.debtToken, amountToSwap, params.minReturnAmount, params.swapData);

        require(returnDebtToken >= totalRepayAmount, UnwindSwapReturnTooLow(totalRepayAmount, returnDebtToken));

        // Repay flash loan
        IERC20(params.debtToken).forceApprove(msg.sender, totalRepayAmount);
        IFlashLoanAdapter(msg.sender).repayFunds(params.debtToken, totalRepayAmount);

        uint256 leftoverDebtToken = IERC20(params.debtToken).balanceOf(address(this));
        if (leftoverDebtToken > 0) {
            IERC20(params.debtToken).safeTransfer(owner(), leftoverDebtToken);
        }

        uint256 leftoverCollateral = IERC20(params.collateralToken).balanceOf(address(this));
        if (leftoverCollateral > 0) {
            IERC20(params.collateralToken).safeTransfer(owner(), leftoverCollateral);
        }

        // Check HF
        checkHF(params.collateralToken, params.lendingPool, params.lendingAdapter);

        emit LeveragePositionUnwound(params.lendingAdapter, params.collateralToken, params.debtToken, amountToSwap);
    }

    /**
     * @notice Move position from one lendgin to other lending
     * @param params Struct MigrationParams has fields:
     * - collateralToken: Address of the collateral token being withdrawn.
     * - collateralAmount: Amount of collateral to withdraw from the source pool and migrate.
     * - debtToken: Address of the token currently borrowed.
     * - debtAmount: Amount of debt to flash-borrow to clear the position in the source pool.
     * - fromPool: Address of the source lending liquidity pool where the position is currently held.
     * - minCollateralToSupply: Minimum acceptable amount of collateral to supply to the new pool.
     * - toPool: Address of the destination lending liquidity pool to migrate the position to.
     * - lendingAdapterFrom: Address of the lending adapter handling the source protocol.
     * - lendingAdapterTo: Address of the lending adapter handling the destination protocol.
     * - flashAdapter: Address of the flashloan adapter handling the flash loan execution.
     * - deadline: Timestamp after which the transaction will revert, protecting the user from delayed execution.
     */
    function migratePosition(MigrationParams calldata params) external onlyOwner deadlineCheck(params.deadline) {
        _validateAdapter(params.lendingAdapterFrom, LENDING_PREFIX);
        _validateAdapter(params.lendingAdapterTo, LENDING_PREFIX);
        _validateAdapter(params.flashAdapter, FLASH_PREFIX);

        TransientBytes.tstore(_PARAMS_SLOT, abi.encode(params));
        _expectedFlashAdapter = params.flashAdapter;
        _currentOperation = Operation.MIGRATE_POSITION;

        // Use flashloan for repay debt
        IFlashLoanAdapter(params.flashAdapter).executeFlashLoan(params.debtToken, params.debtAmount);

        _expectedFlashAdapter = address(0);
    }

    function _executeMigration(MigrationParams memory params) internal {
        uint256 totalRepayAmount = IFlashLoanAdapter(msg.sender).getFullRepayAmount(params.debtToken, params.debtAmount);

        // Repay and withdraw collateral from old lending
        (bool successFrom, bytes memory reason) = params.lendingAdapterFrom
            .delegatecall(
                abi.encodeWithSelector(
                    ILendingAdapter.repayAndWithdraw.selector,
                    params.fromPool,
                    params.collateralToken,
                    params.collateralAmount,
                    params.debtToken,
                    params.debtAmount
                )
            );
        require(successFrom, AdapterExecutionFailed(reason));

        uint256 amountToSupply = params.collateralAmount;
        if (amountToSupply == type(uint256).max) {
            amountToSupply = IERC20(params.collateralToken).balanceOf(address(this));
        }

        require(
            amountToSupply >= params.minCollateralToSupply,
            InsufficientCollateralRecovered(params.minCollateralToSupply, amountToSupply)
        );

        // Supply and borrow
        bool successTo;
        (successTo, reason) = params.lendingAdapterTo
            .delegatecall(
                abi.encodeWithSelector(
                    ILendingAdapter.supplyAndBorrow.selector,
                    params.toPool,
                    params.collateralToken,
                    amountToSupply,
                    params.debtToken,
                    totalRepayAmount
                )
            );
        require(successTo, AdapterExecutionFailed(reason));

        // Repay flashloan
        IERC20(params.debtToken).forceApprove(msg.sender, totalRepayAmount);
        IFlashLoanAdapter(msg.sender).repayFunds(params.debtToken, totalRepayAmount);

        // Check helth faactor in NEW lending
        checkHF(params.collateralToken, params.toPool, params.lendingAdapterTo);

        _sendLeftovers(owner(), params.collateralToken);
        _sendLeftovers(owner(), params.debtToken);

        emit PositionMigrated(
            params.lendingAdapterFrom, params.lendingAdapterTo, params.collateralToken, params.debtToken
        );
    }

    function recoverTokens(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }

    function supplyCollateral(address lendingAdapter, address pool, address collateralToken, uint256 amount)
        external
        onlyOwner
    {
        _validateAdapter(lendingAdapter, LENDING_PREFIX);

        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), amount);

        // Supply
        (bool success, bytes memory reason) = lendingAdapter.delegatecall(
            abi.encodeWithSelector(
                ILendingAdapter.supplyAndBorrow.selector, pool, collateralToken, amount, address(0), 0
            )
        );

        require(success, AdapterExecutionFailed(reason));

        emit CollateralAdded(msg.sender, collateralToken, amount);
    }

    function repayDebt(address lendingAdapter, address pool, address debtToken, uint256 amount) external onlyOwner {
        _validateAdapter(lendingAdapter, LENDING_PREFIX);

        IERC20(debtToken).safeTransferFrom(msg.sender, address(this), amount);

        // Repay
        (bool success, bytes memory reason) = lendingAdapter.delegatecall(
            abi.encodeWithSelector(ILendingAdapter.repayAndWithdraw.selector, pool, address(0), 0, debtToken, amount)
        );

        require(success, AdapterExecutionFailed(reason));

        emit DebtRepaid(msg.sender, debtToken, amount);
    }

    /**
     * @notice Claims liquidity mining or protocol-specific rewards from a lending protocol.
     * @param lendingAdapter Address of lending
     * @param pool Address of the lending pool from which to claim rewards.
     * @param collateralToken Address of the collateral token associated with the rewards.
     * @param debtToken Address of the debt token associated with the rewards.
     * @param rewardContract Address of the protocol's reward/incentives controller contract.
     * @param to Recipient address where the claimed reward tokens will be sent.
     */
    function claimProtocolRewards(
        address lendingAdapter,
        address pool,
        address collateralToken,
        address debtToken,
        address rewardContract,
        address to
    ) external onlyOwner {
        _validateAdapter(lendingAdapter, LENDING_PREFIX);

        (bool success, bytes memory reason) = lendingAdapter.delegatecall(
            abi.encodeWithSelector(
                ILendingAdapter.claimRewards.selector, pool, collateralToken, debtToken, rewardContract, to
            )
        );

        require(success, AdapterExecutionFailed(reason));
    }

    /*
     * @notice Executes a manual borrow operation from the specified lending pool.
      * @param lendingAdapter Address of the Ledero lending adapter.
     * @param pool Address of the lending liquidity pool.
     * @param borrowToken Address of the underlying asset to borrow.
     * @param amount Exact amount of the asset to borrow.
     */
    function borrowDebt(address lendingAdapter, address pool, address borrowToken, uint256 amount) external onlyOwner {
        _validateAdapter(lendingAdapter, LENDING_PREFIX);

        (bool success, bytes memory reason) = lendingAdapter.delegatecall(
            abi.encodeWithSelector(ILendingAdapter.supplyAndBorrow.selector, pool, address(0), 0, borrowToken, amount)
        );

        require(success, AdapterExecutionFailed(reason));

        IERC20(borrowToken).safeTransfer(msg.sender, amount);
    }

    function receiveFlashLoan() external override {
        require(msg.sender == _expectedFlashAdapter, UnauthorizedCallback());
        _expectedFlashAdapter = address(0);

        Operation op = _currentOperation;
        _currentOperation = Operation.NONE;

        bytes memory rawParams = TransientBytes.tload(_PARAMS_SLOT);
        TransientBytes.tstore(_PARAMS_SLOT, "");

        if (op == Operation.OPEN_POSITION) {
            OpenPositionParams memory params = abi.decode(rawParams, (OpenPositionParams));
            _executeOpenPosition(params);
        } else if (op == Operation.UNWIND_POSITION) {
            UnwindPositionParams memory params = abi.decode(rawParams, (UnwindPositionParams));
            _executeUnwindPosition(params);
        } else if (op == Operation.MIGRATE_POSITION) {
            MigrationParams memory params = abi.decode(rawParams, (MigrationParams));
            _executeMigration(params);
        } else {
            revert UnknownOperation();
        }
    }

    function _sendLeftovers(address user, address token) internal {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(user, balance);
        }
    }

    function _validateAdapter(address adapter, uint8 expectedPrefix) internal pure {
        require(adapter != address(0), AdapterAddressZero());

        // 0x0000.....
        require((uint160(adapter) >> 144) == 0, InvalidVanityAddress());

        // 0x0000X == X ?
        uint8 prefix = uint8(uint160(adapter) >> 140) & 0x0F;

        require(prefix == expectedPrefix, InvalidAdapterPrefix());
    }

    function checkHF(address collateralToken, address pool, address lendingAdapter) internal view {
        uint256 currentHF =
            ILendingAdapter(lendingAdapter).getPositionHealthFactor(pool, address(this), collateralToken);

        require(currentHF == type(uint256).max || currentHF >= MIN_SAFE_HF, PositionHealthTooLow());
    }
}
