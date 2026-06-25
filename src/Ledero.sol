// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {LeverageMath} from "./libraries/LeverageMath.sol";
import {ILendingAdapter} from "./interfaces/internal/ILendingAdapter.sol";
import {IFlashLoanAdapter} from "./interfaces/internal/IFlashLoanAdapter.sol";
import {ISwapAdapter} from "./interfaces/internal/ISwapAdapter.sol";
import {TransientContext} from "./base/TransientContext.sol";
import {ActionExecutor} from "./base/ActionExecutor.sol";
import {Constants} from "./base/Constants.sol";
import {ILedero} from "./interfaces/ILedero.sol";
import {
    OpenPositionParams,
    UnwindPositionParams,
    MigrationParams,
    Operation
} from "./interfaces/internal/ILederoTypes.sol";

contract Ledero is
    ILedero,
    Initializable,
    ReentrancyGuardTransient,
    Ownable2StepUpgradeable,
    ActionExecutor,
    TransientContext,
    Constants
{
    using LeverageMath for uint256;
    using SafeERC20 for IERC20;

    modifier deadlineCheck(uint256 deadline) {
        _checkDeadline(deadline);
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
        payable
        nonReentrant
        onlyOwner
        deadlineCheck(params.deadline)
    {
        _validateAdapter(params.lendingAdapter, LENDING_PREFIX);
        _validateAdapter(params.flashAdapter, FLASH_PREFIX);
        _validateAdapter(params.swapAdapter, SWAP_PREFIX);

        // Transfer initial amount from user
        IERC20(params.collateralToken).safeTransferFrom(msg.sender, address(this), params.collateralAmount);

        _initiateFlashloan(params.flashAdapter, Operation.OPEN_POSITION, params.collateralToken, params.flashLoanAmount);
    }

    function _executeOpenPosition(OpenPositionParams calldata params, address expectedFlashAdapter) internal {
        address collateralToken = params.collateralToken;
        address lendingAdapter = params.lendingAdapter;
        address lendingPool = params.lendingPool;

        _executeActions(
            IFlashLoanAdapter(expectedFlashAdapter).takeFundsSecondStep(collateralToken, params.flashLoanAmount)
        );
        // Supply and borrow
        uint256 totalCollateral = params.collateralAmount + params.flashLoanAmount;
        _executeActions(
            ILendingAdapter(lendingAdapter)
                .supplyAndBorrow(lendingPool, collateralToken, totalCollateral, params.borrowToken, params.borrowAmount)
        );
        // Swap
        _executeActions(ISwapAdapter(params.swapAdapter).swap(params.borrowToken, params.borrowAmount, params.swapData));
        // Check slippage
        uint256 totalRepayAmount =
            IFlashLoanAdapter(expectedFlashAdapter).getFullRepayAmount(collateralToken, params.flashLoanAmount);
        uint256 balanceAfterSwap = IERC20(collateralToken).balanceOf(address(this));
        if (balanceAfterSwap < totalRepayAmount) {
            revert InsufficientSwapReturnForFlashLoan(totalRepayAmount, balanceAfterSwap);
        }

        // Repay flashloan
        _executeActions(IFlashLoanAdapter(expectedFlashAdapter).repayFunds(collateralToken, totalRepayAmount));
        // Supply dust
        uint256 leftover;
        unchecked {
            leftover = balanceAfterSwap - totalRepayAmount;
        }
        if (leftover > 0) {
            _executeActions(
                ILendingAdapter(lendingAdapter).supplyAndBorrow(lendingPool, collateralToken, leftover, address(0), 0)
            );
        }

        _checkHf(collateralToken, lendingPool, lendingAdapter);

        emit LeveragePositionCreated(
            lendingAdapter, totalCollateral + leftover, params.borrowAmount, collateralToken, params.borrowToken
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
     * - minReturnAmount: Minimum acceptable amount of `debtToken` to receive from the swap.
     * - lendingAdapter: Address of the Ledero adapter for the specific lending protocol.
     * - flashAdapter: Address of the Ledero adapter handling the flash loan.
     * - swapAdapter: Address of the Ledero adapter handling the swap aggregation.
     * - deadline: Timestamp after which the transaction will revert, protecting the user from delayed execution and worse prices.
     * - swapData: Encoded payload provided by the swap aggregator API.
     */
    function unwindPosition(UnwindPositionParams calldata params)
        external
        payable
        nonReentrant
        onlyOwner
        deadlineCheck(params.deadline)
    {
        _validateAdapter(params.lendingAdapter, LENDING_PREFIX);
        _validateAdapter(params.swapAdapter, SWAP_PREFIX);
        _validateAdapter(params.flashAdapter, FLASH_PREFIX);

        _initiateFlashloan(params.flashAdapter, Operation.UNWIND_POSITION, params.debtToken, params.debtToRepay);
    }

    function _executeUnwindPosition(UnwindPositionParams calldata params, address expectedFlashAdapter) internal {
        address collateralToken = params.collateralToken;
        address debtToken = params.debtToken;
        address lendingAdapter = params.lendingAdapter;
        address lendingPool = params.lendingPool;
        uint256 debtToRepay = params.debtToRepay;
        uint256 collateralToWithdraw = params.collateralToWithdraw;

        _executeActions(IFlashLoanAdapter(expectedFlashAdapter).takeFundsSecondStep(debtToken, debtToRepay));

        // Repay and withdraw collateral
        _executeActions(
            ILendingAdapter(lendingAdapter)
                .repayAndWithdraw(lendingPool, collateralToken, collateralToWithdraw, debtToken, debtToRepay)
        );
        // Swap collateral to debt
        uint256 amountToSwap = collateralToWithdraw == type(uint256).max
            ? IERC20(collateralToken).balanceOf(address(this))
            : collateralToWithdraw;

        uint256 debtBalanceBefore = IERC20(debtToken).balanceOf(address(this));

        _executeActions(ISwapAdapter(params.swapAdapter).swap(collateralToken, amountToSwap, params.swapData));

        uint256 debtBalanceAfter = IERC20(debtToken).balanceOf(address(this));

        uint256 returnAmount;
        unchecked {
            returnAmount = debtBalanceAfter - debtBalanceBefore;
        }

        if (returnAmount < params.minReturnAmount) {
            revert UnwindSwapReturnTooLow(params.minReturnAmount, returnAmount);
        }

        // Repay flashloan
        uint256 totalRepayAmount = IFlashLoanAdapter(expectedFlashAdapter).getFullRepayAmount(debtToken, debtToRepay);

        _executeActions(IFlashLoanAdapter(expectedFlashAdapter).repayFunds(debtToken, totalRepayAmount));

        uint256 debtLeftover;
        unchecked {
            debtLeftover = debtBalanceAfter - totalRepayAmount;
        }
        if (debtLeftover > 0) {
            IERC20(debtToken).safeTransfer(owner(), debtLeftover);
        }

        _sendLeftovers(owner(), collateralToken);

        _checkHf(collateralToken, lendingPool, lendingAdapter);

        emit LeveragePositionUnwound(lendingAdapter, debtToken, amountToSwap, collateralToken);
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
    function migratePosition(MigrationParams calldata params)
        external
        payable
        nonReentrant
        onlyOwner
        deadlineCheck(params.deadline)
    {
        _validateAdapter(params.lendingAdapterFrom, LENDING_PREFIX);
        _validateAdapter(params.lendingAdapterTo, LENDING_PREFIX);
        _validateAdapter(params.flashAdapter, FLASH_PREFIX);

        _initiateFlashloan(params.flashAdapter, Operation.MIGRATE_POSITION, params.debtToken, params.debtAmount);
    }

    function _executeMigration(MigrationParams calldata params, address expectedFlashAdapter) internal {
        address collateralToken = params.collateralToken;
        address debtToken = params.debtToken;
        address lendingAdapterFrom = params.lendingAdapterFrom;
        address lendingAdapterTo = params.lendingAdapterTo;
        address toPool = params.toPool;
        uint256 collateralAmount = params.collateralAmount;
        uint256 debtAmount = params.debtAmount;

        _executeActions(IFlashLoanAdapter(expectedFlashAdapter).takeFundsSecondStep(debtToken, debtAmount));

        uint256 totalRepayAmount = IFlashLoanAdapter(expectedFlashAdapter).getFullRepayAmount(debtToken, debtAmount);

        // Repay and withdraw collateral from old lending
        _executeActions(
            ILendingAdapter(lendingAdapterFrom)
                .repayAndWithdraw(params.fromPool, collateralToken, collateralAmount, debtToken, debtAmount)
        );

        uint256 amountToSupply =
            collateralAmount == type(uint256).max ? IERC20(collateralToken).balanceOf(address(this)) : collateralAmount;

        uint256 minCol = params.minCollateralToSupply;
        if (amountToSupply < minCol) {
            revert InsufficientCollateralRecovered(minCol, amountToSupply);
        }

        // Supply and borrow
        _executeActions(
            ILendingAdapter(lendingAdapterTo)
                .supplyAndBorrow(toPool, collateralToken, amountToSupply, debtToken, totalRepayAmount)
        );
        // Repay flashloan
        _executeActions(IFlashLoanAdapter(expectedFlashAdapter).repayFunds(debtToken, totalRepayAmount));
        // Check helth faactor in NEW lending
        _checkHf(collateralToken, toPool, lendingAdapterTo);

        _sendLeftovers(owner(), collateralToken);
        _sendLeftovers(owner(), debtToken);

        emit PositionMigrated(lendingAdapterFrom, lendingAdapterTo, collateralToken, debtToken);
    }

    function recoverTokens(address _token, uint256 _amount) external payable onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }

    function supplyCollateral(address lendingAdapter, address pool, address collateralToken, uint256 amount)
        external
        payable
        nonReentrant
        onlyOwner
    {
        _validateAdapter(lendingAdapter, LENDING_PREFIX);

        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), amount);

        // Supply
        _executeActions(ILendingAdapter(lendingAdapter).supplyAndBorrow(pool, collateralToken, amount, address(0), 0));

        emit CollateralAdded(msg.sender, collateralToken, amount);
    }

    function repayDebt(address lendingAdapter, address pool, address debtToken, uint256 amount)
        external
        payable
        nonReentrant
        onlyOwner
    {
        _validateAdapter(lendingAdapter, LENDING_PREFIX);

        IERC20(debtToken).safeTransferFrom(msg.sender, address(this), amount);

        // Repay
        _executeActions(ILendingAdapter(lendingAdapter).repayAndWithdraw(pool, address(0), 0, debtToken, amount));

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
    ) external payable nonReentrant onlyOwner {
        _validateAdapter(lendingAdapter, LENDING_PREFIX);

        _executeActions(
            ILendingAdapter(lendingAdapter).claimRewards(pool, collateralToken, debtToken, rewardContract, to)
        );
    }

    /*
     * @notice Executes a manual borrow operation from the specified lending pool.
     * @param lendingAdapter Address of the Ledero lending adapter.
     * @param pool Address of the lending liquidity pool.
     * @param borrowToken Address of the underlying asset to borrow.
     * @param amount Exact amount of the asset to borrow.
     */
    function borrowDebt(address lendingAdapter, address pool, address borrowToken, uint256 amount)
        external
        payable
        nonReentrant
        onlyOwner
    {
        _validateAdapter(lendingAdapter, LENDING_PREFIX);

        _executeActions(ILendingAdapter(lendingAdapter).supplyAndBorrow(pool, address(0), 0, borrowToken, amount));

        IERC20(borrowToken).safeTransfer(msg.sender, amount);
    }

    function receiveFlashLoan(bytes calldata rawParams) external payable override {
        (address _expectedFlashAdapter, Operation op) = _getTransientContext();
        _clearTransientContext();

        if (msg.sender != IFlashLoanAdapter(_expectedFlashAdapter).VAULT()) revert UnauthorizedCallback();

        if (op == Operation.OPEN_POSITION) {
            OpenPositionParams calldata params;
            assembly ("memory-safe") { params := add(rawParams.offset, 0x20) }
            _executeOpenPosition(params, _expectedFlashAdapter);
        } else if (op == Operation.UNWIND_POSITION) {
            UnwindPositionParams calldata params;
            assembly ("memory-safe") { params := add(rawParams.offset, 0x20) }
            _executeUnwindPosition(params, _expectedFlashAdapter);
        } else if (op == Operation.MIGRATE_POSITION) {
            MigrationParams calldata params;
            assembly ("memory-safe") { params := rawParams.offset }
            _executeMigration(params, _expectedFlashAdapter);
        }
    }

    function _sendLeftovers(address user, address token) internal {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(user, balance);
        }
    }

    function _validateAdapter(address adapter, uint8 expectedPrefix) internal pure {
        // 0x0000X == X ?
        if (uint160(adapter) >> 140 != expectedPrefix) revert InvalidAdapterPrefix();
    }

    function _checkHf(address collateralToken, address pool, address lendingAdapter) internal view {
        uint256 currentHf =
            ILendingAdapter(lendingAdapter).getPositionHealthFactor(pool, address(this), collateralToken);

        if (currentHf < MIN_SAFE_HF) revert PositionHealthTooLow();
    }

    /**
     * [selector(4 bytes)][offset(32 bytes)][length (32 bytres)][data struct]
     *
     */
    function _initiateFlashloan(address flashAdapter, Operation op, address tokenToBorrow, uint256 amountToBorrow)
        internal
    {
        _setTransientContext(flashAdapter, op);

        bytes4 selector = this.receiveFlashLoan.selector;
        bytes memory userData;

        assembly ("memory-safe") {
            // length without selector
            let paramsSize := sub(calldatasize(), 0x04)

            userData := mload(0x40)
            // 0x44 (full length)= 4(selector) + 32(offset) + 32(paramsSize) = 68 = 0x44
            mstore(userData, add(0x44, paramsSize))
            // 4 bytes selector - receiveFlashLoan()
            mstore(add(userData, 0x20), selector)
            // offset - start mstore from previous start place + 4 bytes
            mstore(add(userData, 0x24), 0x20)
            // length of rawParams
            mstore(add(userData, 0x44), paramsSize)
            // input struct
            calldatacopy(add(userData, 0x64), 0x04, paramsSize)
            // write new fmp
            mstore(0x40, add(add(userData, 0x64), paramsSize))
        }

        _executeActions(IFlashLoanAdapter(flashAdapter).takeFundsFirstStep(tokenToBorrow, amountToBorrow, userData));
    }

    function _checkDeadline(uint256 deadline) private view {
        if (block.timestamp > deadline) revert ExpiredDeadline();
    }
}
