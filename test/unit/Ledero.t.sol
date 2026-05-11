// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {Ledero} from "../../src/Ledero.sol";
import {LederoBase} from "../base/LederoBase.t.sol";
import {LederoOracle} from "../../src/LederoOracle.sol";
import {ConstantsEtMainnet} from "../Constants.t.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockBalancer} from "../mock/MockBalancer.sol";
import {BalancerV3Adapter} from "../../src/adapters/loan/BalancerV3.sol";
import {MockLendingAdapter} from "../mock/MockLendingAdapter.sol";
import {Mock1InchRouter} from "../mock/Mock1InchRouter.sol";
import {IFlashLoanAdapter} from "../../src/interfaces/internal/IFlashLoanAdapter.sol";
import {ILendingAdapter} from "../../src/interfaces/internal/ILendingAdapter.sol";
import {ConstantsEtMainnet} from "../Constants.t.sol";
import {OneInchAdapter} from "../../src/adapters/swap/OneInch.sol";
import {CompoundV3Adapter} from "../../src/adapters/lendings/CompoundV3.sol";
import {RevertAllMock} from "../utils/Revert.sol";
import {ISwapAdapter} from "../../src/interfaces/internal/ISwapAdapter.sol";
import "../../src/interfaces/internal/IConstants.sol";
import "../../src/interfaces/internal/ILederoTypes.sol";
import "../../src/interfaces/internal/ILederoErrors.sol";

contract LederoUnitTest is Test, LederoBase {
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    Mock1InchRouter public mockRouter;
    MockBalancer public mockVault;

    function _deployFlashAndSwapAdapters() internal override {
        mockRouter = new Mock1InchRouter();
        mockVault = new MockBalancer();

        BalancerV3Adapter tempBalancer = new BalancerV3Adapter(address(mockVault), address(ledero));
        balancerAdapter = BalancerV3Adapter(_etchToVanity(address(tempBalancer), FLASH_PREFIX, 99));

        OneInchAdapter tempSwap = new OneInchAdapter(address(mockRouter), address(ledero));
        swapAdapter = OneInchAdapter(_etchToVanity(address(tempSwap), SWAP_PREFIX, 100));
    }

    function setUp() public override {
        super.setUp();
        tokenA = new MockERC20("TokenA", "TKNA");
        tokenB = new MockERC20("TokenB", "TKNB");

        deal(address(tokenA), owner, 1 ether);
        deal(address(tokenA), address(balancerAdapter), 2 ether);
    }

    function test_ContractDeployment() public view {
        assertEq(ledero.owner(), owner, "Wrong owner");
    }

    function test_BeaconProxySetup() public view {
        assertEq(beacon.implementation(), address(lederoImplementation), "Wrong implementation");
        assertEq(address(ledero), address(proxy), "Ledero is not proxy");
    }

    function test_OnlyOwnerCanRecoverTokens() public {
        address hacker = makeAddr("hacker");
        bytes memory expectedError = abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", hacker);
        vm.expectRevert(expectedError);
        vm.prank(hacker);
        ledero.recoverTokens(address(0x123), 100e6);
    }

    function test_OwnerCanRecoverTokensSuccessfully() public {
        MockERC20 mockToken = new MockERC20("Mock Token", "MTK");
        uint256 amount = 100e6;
        mockToken.mint(address(ledero), amount);
        uint256 ownerBalanceBefore = mockToken.balanceOf(owner);

        vm.prank(owner);
        ledero.recoverTokens(address(mockToken), amount);

        assertEq(mockToken.balanceOf(address(ledero)), 0, "Tokens on ledero");
        assertEq(mockToken.balanceOf(owner), ownerBalanceBefore + amount, "Owner should receive the tokens");
    }

    function test_FullTwoStepOwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        ledero.transferOwnership(newOwner);

        assertEq(ledero.owner(), owner, "Wrong owner");
        assertEq(ledero.pendingOwner(), newOwner, "Wrong pending owner");

        vm.prank(newOwner);
        ledero.acceptOwnership();

        assertEq(ledero.owner(), newOwner, "Owner should now be newOwner");
        assertEq(ledero.pendingOwner(), address(0), "Pending owner should be reset");
    }

    function test_RevertIf_OpenPositionLendingAdapterFail() public {
        deal(address(tokenB), address(ledero), 1 ether);
        vm.prank(owner);
        tokenA.approve(address(ledero), type(uint256).max);
        OpenPositionParams memory params = _getDefaultOpenPositionParams();

        vm.etch(address(compoundAdapter), address(new RevertAllMock()).code);

        deal(address(tokenA), address(mockVault), 5 ether);
        vm.prank(owner);
        bytes memory expectedReason = abi.encodeWithSelector(RevertAllMock.AdapterIsDead.selector);
        vm.expectRevert(abi.encodeWithSelector(AdapterExecutionFailed.selector, expectedReason));
        ledero.createLeveragedPosition(params);
    }

    function test_RevertIf_OpenPositionInsufficientSwapReturnForFlashLoan() public {
        deal(address(tokenB), address(ledero), 1 ether);
        vm.prank(owner);
        tokenA.approve(address(ledero), type(uint256).max);
        OpenPositionParams memory params = _getDefaultOpenPositionParams();

        deal(address(tokenA), address(mockVault), 5 ether);
        vm.prank(owner);
        vm.mockCall(
            address(compoundAdapter), abi.encodeWithSelector(ILendingAdapter.supplyAndBorrow.selector), abi.encode()
        );
        vm.mockCall(address(swapAdapter), abi.encodeWithSelector(ISwapAdapter.swap.selector), abi.encode(1 ether));

        vm.expectRevert(abi.encodeWithSelector(InsufficientSwapReturnForFlashLoan.selector, 2 ether, 1 ether));
        ledero.createLeveragedPosition(params);
    }

    function test_RevertIf_OpenPositionLeftOverSupplyFail() public {
        deal(address(tokenB), address(ledero), 1 ether);
        vm.prank(owner);
        tokenA.approve(address(ledero), type(uint256).max);
        OpenPositionParams memory params = _getDefaultOpenPositionParams();

        deal(address(tokenA), address(mockVault), 5 ether);
        vm.prank(owner);
        vm.mockCall(
            address(compoundAdapter), abi.encodeWithSelector(ILendingAdapter.supplyAndBorrow.selector), abi.encode()
        );
        vm.mockCall(address(swapAdapter), abi.encodeWithSelector(ISwapAdapter.swap.selector), abi.encode(3 ether));

        bytes memory mockError = abi.encodeWithSignature("DustFailure()");

        bytes memory exactCallData = abi.encodeWithSelector(
            ILendingAdapter.supplyAndBorrow.selector, address(123), address(tokenA), 1 ether, address(0), 0
        );

        vm.mockCallRevert(params.lendingAdapter, exactCallData, mockError);

        vm.expectRevert(abi.encodeWithSelector(AdapterExecutionFailed.selector, mockError));
        ledero.createLeveragedPosition(params);
    }

    // Unwind

    function test_RevertIf_UnwindPositionRepayFail() public {
        UnwindPositionParams memory params = _getDefaultUnwindPositionParams();

        deal(address(tokenA), address(mockVault), 1 ether);
        bytes memory innerError = abi.encodeWithSignature("ERC20InvalidSpender(address)", address(0));

        vm.expectRevert(abi.encodeWithSelector(AdapterExecutionFailed.selector, innerError));
        vm.prank(owner);
        ledero.unwindPosition(params);
    }

    function test_RevertIf_UnwindPositionUnwindSwapReturnTooLow() public {
        UnwindPositionParams memory params = _getDefaultUnwindPositionParams();
        params.collateralToWithdraw = type(uint256).max;
        params.collateralToken = address(tokenB);

        vm.mockCall(
            address(compoundAdapter), abi.encodeWithSelector(ILendingAdapter.repayAndWithdraw.selector), abi.encode()
        );

        vm.mockCall(address(swapAdapter), abi.encodeWithSelector(ISwapAdapter.swap.selector), abi.encode(1));

        deal(address(tokenA), address(mockVault), 1 ether);
        deal(address(tokenB), address(ledero), 1 ether);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(UnwindSwapReturnTooLow.selector, 1 ether, 1));
        ledero.unwindPosition(params);
    }

    function test_RevertIf_UnwindPositionPositionHealthTooLow() public {
        UnwindPositionParams memory params = _getDefaultUnwindPositionParams();
        params.lendingPool = address(456);

        vm.mockCall(
            address(compoundAdapter), abi.encodeWithSelector(ILendingAdapter.repayAndWithdraw.selector), abi.encode()
        );

        vm.mockCall(address(swapAdapter), abi.encodeWithSelector(ISwapAdapter.swap.selector), abi.encode(2 ether));

        vm.mockCall(
            address(compoundAdapter),
            abi.encodeWithSelector(ILendingAdapter.getPositionHealthFactor.selector),
            abi.encode(1 ether)
        );
        deal(address(tokenA), address(mockVault), 1 ether);
        deal(address(tokenB), address(ledero), 4 ether);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PositionHealthTooLow.selector));
        ledero.unwindPosition(params);
    }

    // Migration
    function test_RevertIf_MigrationRepayFail() public {
        deal(address(tokenA), address(mockVault), 1 ether);
        vm.prank(owner);
        MigrationParams memory params = _getDefaultMigrationPositionParams();
        params.debtToken = address(tokenA);

        bytes memory mockError = abi.encodeWithSignature("lendingError()");
        bytes memory exactCallData = abi.encodeWithSelector(
            ILendingAdapter.repayAndWithdraw.selector,
            params.fromPool,
            params.collateralToken,
            params.collateralAmount,
            params.debtToken,
            params.debtAmount
        );

        vm.mockCallRevert(params.lendingAdapterFrom, exactCallData, mockError);

        vm.expectRevert(abi.encodeWithSelector(AdapterExecutionFailed.selector, mockError));
        ledero.migratePosition(params);
    }

    function test_RevertIf_MigrationCollateralAmountMax() public {
        deal(address(tokenA), address(mockVault), 1 ether);
        deal(address(tokenB), address(ledero), 1 ether);
        vm.prank(owner);
        MigrationParams memory params = _getDefaultMigrationPositionParams();
        params.collateralAmount = type(uint256).max;

        bytes memory exactCallData = abi.encodeWithSelector(
            ILendingAdapter.repayAndWithdraw.selector,
            params.fromPool,
            params.collateralToken,
            params.collateralAmount,
            params.debtToken,
            params.debtAmount
        );
        vm.mockCall(address(compoundAdapter), exactCallData, abi.encode());

        bytes memory innerError = abi.encodeWithSignature("ERC20InvalidSpender(address)", address(0));

        vm.expectRevert(abi.encodeWithSelector(AdapterExecutionFailed.selector, innerError));
        ledero.migratePosition(params);
    }

    function test_RevertIf_MigrationInsufficientCollateralRecovered() public {
        deal(address(tokenA), address(mockVault), 1 ether);
        deal(address(tokenB), address(ledero), 1 ether);
        vm.prank(owner);
        MigrationParams memory params = _getDefaultMigrationPositionParams();
        params.minCollateralToSupply = 10 ether;
        params.collateralAmount = 1 ether;
        bytes memory exactCallData = abi.encodeWithSelector(
            ILendingAdapter.repayAndWithdraw.selector,
            params.fromPool,
            params.collateralToken,
            params.collateralAmount,
            params.debtToken,
            params.debtAmount
        );
        vm.mockCall(address(compoundAdapter), exactCallData, abi.encode());

        vm.expectRevert(abi.encodeWithSelector(InsufficientCollateralRecovered.selector, 10 ether, 1 ether));
        ledero.migratePosition(params);
    }

    function test_RevertIf_Migration4SupplyToFail() public {
        deal(address(tokenA), address(mockVault), 1 ether);
        deal(address(tokenB), address(ledero), 1 ether);

        vm.prank(owner);
        MigrationParams memory params = _getDefaultMigrationPositionParams();
        params.minCollateralToSupply = 1 ether;
        params.collateralAmount = 10 ether;
        bytes memory exactCallData = abi.encodeWithSelector(
            ILendingAdapter.repayAndWithdraw.selector,
            params.fromPool,
            params.collateralToken,
            params.collateralAmount,
            params.debtToken,
            params.debtAmount
        );
        vm.mockCall(address(compoundAdapter), exactCallData, abi.encode());

        bytes memory innerError = abi.encodeWithSignature("ERC20InvalidSpender(address)", address(0));

        vm.expectRevert(abi.encodeWithSelector(AdapterExecutionFailed.selector, innerError));

        ledero.migratePosition(params);
    }

    function test_Migration_SendsLeftoversToOwner() public {
        MigrationParams memory params = _getDefaultMigrationPositionParams();

        uint256 extraCollateral = 1 ether;
        uint256 extraDebt = 1 ether;

        uint256 requiredRepay = 1 ether;
        params.debtAmount = 1 ether;
        deal(params.debtToken, address(mockVault), 2 ether);
        deal(params.debtToken, address(ledero), 1 ether);
        deal(params.collateralToken, address(ledero), 1 ether);

        uint256 ownerCollateralBefore = IERC20(params.collateralToken).balanceOf(owner); // 0
        uint256 ownerDebtBefore = IERC20(params.debtToken).balanceOf(owner); // 1 ether

        vm.mockCall(
            params.lendingAdapterFrom, abi.encodeWithSelector(ILendingAdapter.repayAndWithdraw.selector), abi.encode()
        );

        vm.mockCall(
            params.lendingAdapterTo, abi.encodeWithSelector(ILendingAdapter.supplyAndBorrow.selector), abi.encode()
        );

        vm.mockCall(
            params.lendingAdapterTo,
            abi.encodeWithSelector(ILendingAdapter.getPositionHealthFactor.selector),
            abi.encode(2 ether)
        );

        vm.prank(owner);
        ledero.migratePosition(params);

        assertEq(
            IERC20(params.collateralToken).balanceOf(owner),
            ownerCollateralBefore + extraCollateral,
            "Collateral leftovers not sent"
        );

        assertEq(IERC20(params.debtToken).balanceOf(owner), ownerDebtBefore + extraDebt, "Debt leftovers not sent");

        assertEq(IERC20(params.collateralToken).balanceOf(address(ledero)), 0);
        assertEq(IERC20(params.debtToken).balanceOf(address(ledero)), 0);
    }

    // Manual operations

    function test_SupplyCollateral() public {
        deal(address(tokenA), owner, 100 ether);

        vm.mockCall(
            address(compoundAdapter), abi.encodeWithSelector(ILendingAdapter.supplyAndBorrow.selector), abi.encode()
        );

        vm.startPrank(owner);
        tokenA.approve(address(ledero), 100 ether);

        ledero.supplyCollateral(address(compoundAdapter), address(123), address(tokenA), 10 ether);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(address(ledero)), 10 ether);
    }

    function test_RevertIf_SupplyCollateralAdapterFails() public {
        deal(address(tokenA), owner, 10 ether);

        vm.startPrank(owner);
        tokenA.approve(address(ledero), 10 ether);

        bytes memory mockError = abi.encodeWithSignature("AdapterFailure()");
        vm.mockCallRevert(
            address(compoundAdapter), abi.encodeWithSelector(ILendingAdapter.supplyAndBorrow.selector), mockError
        );

        vm.expectRevert(abi.encodeWithSelector(AdapterExecutionFailed.selector, mockError));

        ledero.supplyCollateral(address(compoundAdapter), address(123), address(tokenA), 10 ether);
        vm.stopPrank();
    }

    function test_RepayDebt() public {
        uint256 repayAmount = 10 ether;
        deal(address(tokenA), owner, repayAmount);

        vm.mockCall(
            address(compoundAdapter), abi.encodeWithSelector(ILendingAdapter.repayAndWithdraw.selector), abi.encode()
        );

        vm.startPrank(owner);
        tokenA.approve(address(ledero), repayAmount);

        ledero.repayDebt(address(compoundAdapter), address(123), address(tokenA), repayAmount);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(address(ledero)), repayAmount);
    }

    function test_RevertIf_RepayDebtAdapterFails() public {
        uint256 repayAmount = 10 ether;
        deal(address(tokenA), owner, repayAmount);

        vm.startPrank(owner);
        tokenA.approve(address(ledero), repayAmount);

        bytes memory mockError = abi.encodeWithSignature("SimulatedRepayFailure()");

        vm.mockCallRevert(
            address(compoundAdapter), abi.encodeWithSelector(ILendingAdapter.repayAndWithdraw.selector), mockError
        );

        vm.expectRevert(abi.encodeWithSelector(AdapterExecutionFailed.selector, mockError));

        ledero.repayDebt(address(compoundAdapter), address(123), address(tokenA), repayAmount);
        vm.stopPrank();
    }

    function test_RevertIf_OpenPositionDeadlineIsZero() public {
        OpenPositionParams memory params;
        vm.prank(owner);
        vm.expectRevert(ExpiredDeadline.selector);
        ledero.createLeveragedPosition(params);
    }

    function test_RevertIf_UnwindPositionDeadlineIsZero() public {
        UnwindPositionParams memory params;
        vm.prank(owner);
        vm.expectRevert(ExpiredDeadline.selector);
        ledero.unwindPosition(params);
    }

    function test_RevertIf_MigrationPositionDeadlineIsZero() public {
        MigrationParams memory params;
        vm.prank(owner);
        vm.expectRevert(ExpiredDeadline.selector);
        ledero.migratePosition(params);
    }

    function test_RevertIf_UnknownOperation() public {
        vm.expectRevert(UnknownOperation.selector);

        vm.prank(address(0));
        ledero.receiveFlashLoan();
    }

    function test_RevertIf_UnauthorizedCallback() public {
        vm.expectRevert(UnauthorizedCallback.selector);

        vm.prank(address(123));
        ledero.receiveFlashLoan();
    }

    function test_BorrowDebt() public {
        uint256 borrowAmount = 5 ether;

        vm.mockCall(
            address(compoundAdapter), abi.encodeWithSelector(ILendingAdapter.supplyAndBorrow.selector), abi.encode()
        );

        deal(address(tokenB), address(ledero), borrowAmount);

        vm.startPrank(owner);

        ledero.borrowDebt(address(compoundAdapter), address(123), address(tokenB), borrowAmount);
        vm.stopPrank();

        assertEq(tokenB.balanceOf(owner), borrowAmount);
    }

    function test_RevertIf_BorrowDebtAddapterFail() public {
        uint256 borrowAmount = 5 ether;

        bytes memory mockError = abi.encodeWithSignature("SimulatedBorrowFailure()");

        vm.mockCallRevert(
            address(compoundAdapter), abi.encodeWithSelector(ILendingAdapter.supplyAndBorrow.selector), mockError
        );

        vm.startPrank(owner);

        vm.expectRevert(abi.encodeWithSelector(AdapterExecutionFailed.selector, mockError));

        ledero.borrowDebt(address(compoundAdapter), address(123), address(tokenB), borrowAmount);
        vm.stopPrank();
    }

    // Claim
    function test_ClaimProtocolRewards() public {
        address mockRewardContract = address(777);
        address recipient = owner;

        vm.mockCall(
            address(compoundAdapter), abi.encodeWithSelector(ILendingAdapter.claimRewards.selector), abi.encode()
        );

        vm.startPrank(owner);
        ledero.claimProtocolRewards(
            address(compoundAdapter), address(123), address(tokenA), address(tokenB), mockRewardContract, recipient
        );
        vm.stopPrank();
    }

    function test_RevertIf_ClaimProtocolRewardsAdapterFails() public {
        address mockRewardContract = address(777);
        address recipient = owner;

        bytes memory mockError = abi.encodeWithSignature("SimulatedClaimFailure()");

        vm.mockCallRevert(
            address(compoundAdapter), abi.encodeWithSelector(ILendingAdapter.claimRewards.selector), mockError
        );

        vm.startPrank(owner);

        vm.expectRevert(abi.encodeWithSelector(AdapterExecutionFailed.selector, mockError));

        ledero.claimProtocolRewards(
            address(compoundAdapter), address(123), address(tokenA), address(tokenB), mockRewardContract, recipient
        );
        vm.stopPrank();
    }

    function test_RevertIf_AdapterAddressZero() public {
        OpenPositionParams memory params = _getDefaultOpenPositionParams();
        params.lendingAdapter = address(0);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AdapterAddressZero.selector));
        ledero.createLeveragedPosition(params);
    }

    function test_RevertIf_AdapterHasInvalidVanityAddress() public {
        OpenPositionParams memory params = _getDefaultOpenPositionParams();
        params.lendingAdapter = address(owner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(InvalidVanityAddress.selector));
        ledero.createLeveragedPosition(params);
    }

    function test_RevertIf_AdapterHasInvalidAdapterPrefix() public {
        OpenPositionParams memory params = _getDefaultOpenPositionParams();
        params.lendingAdapter = address(swapAdapter);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(InvalidAdapterPrefix.selector));
        ledero.createLeveragedPosition(params);
    }

    function _getDefaultOpenPositionParams() internal view returns (OpenPositionParams memory params) {
        params.deadline = block.timestamp;
        params.flashLoanAmount = 2 ether;
        params.lendingAdapter = address(compoundAdapter);
        params.flashAdapter = address(balancerAdapter);
        params.swapAdapter = address(swapAdapter);
        params.collateralToken = address(tokenA);
        params.collateralAmount = 1 ether;
        params.lendingPool = address(123);
        params.borrowToken = address(tokenB);
        params.borrowAmount = 1 ether;
    }

    function _getDefaultUnwindPositionParams() internal view returns (UnwindPositionParams memory params) {
        params.deadline = block.timestamp;
        params.lendingAdapter = address(compoundAdapter);
        params.flashAdapter = address(balancerAdapter);
        params.swapAdapter = address(swapAdapter);
        params.debtToken = address(tokenA);
        params.debtToRepay = 1 ether;
        params.collateralToWithdraw = 2 ether;
        params.collateralToken = address(tokenB);
    }

    function _getDefaultMigrationPositionParams() internal view returns (MigrationParams memory params) {
        params.deadline = block.timestamp;
        params.lendingAdapterFrom = address(compoundAdapter);
        params.lendingAdapterTo = address(compoundAdapter);
        params.flashAdapter = address(balancerAdapter);
        params.debtToken = address(tokenA);
        params.collateralToken = address(tokenB);
    }
}
