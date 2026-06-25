// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {LederoBase} from "../base/LederoBase.t.sol";
import {LederoOracle} from "../../src/LederoOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AaveV3Adapter} from "../../src/adapters/lendings/AaveV3.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockBalancer} from "../mock/MockBalancer.sol";
import {BalancerV3Adapter} from "../../src/adapters/loan/BalancerV3.sol";
import {Mock1InchRouter} from "../mock/Mock1InchRouter.sol";
import {IFlashLoanAdapter} from "../../src/interfaces/internal/IFlashLoanAdapter.sol";
import {ILendingAdapter} from "../../src/interfaces/internal/ILendingAdapter.sol";
import {OneInchAdapter} from "../../src/adapters/swap/OneInch.sol";
import {CompoundV3Adapter} from "../../src/adapters/lendings/CompoundV3.sol";
import {ISwapAdapter} from "../../src/interfaces/internal/ISwapAdapter.sol";
import {MockCompoundRewardsController} from "../mock/MockCompoundRewardsController.sol";
import {MockComet} from "../mock/MockComet.sol";
import {MockAavePool} from "../mock/MockAavePool.sol";
import {Constants} from "../../src/base/Constants.sol";
import {OpenPositionParams, UnwindPositionParams, AdapterAction} from "../../src/interfaces/internal/ILederoTypes.sol";
import {ILederoErrors} from "../../src/interfaces/internal/ILederoErrors.sol";

import {
    OpenPositionParams,
    UnwindPositionParams,
    MigrationParams,
    AdapterAction
} from "../../src/interfaces/internal/ILederoTypes.sol";

contract LederoUnitTest is Test, ILederoErrors, Constants, LederoBase {
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    Mock1InchRouter public mockRouter;
    MockBalancer public mockVault;
    MockCompoundRewardsController public compoundRewardController;
    MockComet public mockComet;
    MockAavePool public mockAavePool;

    function _deployOracle() internal override {
        oracle = new LederoOracle();
    }

    function _setupPermissions() internal override {
        ledero.transferOwnership(owner);
        vm.startPrank(owner);
        ledero.acceptOwnership();
        vm.stopPrank();
    }

    function _deployLendingAdapters() internal override {
        AaveV3Adapter tempAave = new AaveV3Adapter();
        CompoundV3Adapter tempCompound = new CompoundV3Adapter();
        aaveAdapter = AaveV3Adapter(_etchToVanity(address(tempAave), LENDING_PREFIX, 1));
        compoundAdapter = CompoundV3Adapter(_etchToVanity(address(tempCompound), LENDING_PREFIX, 2));
    }

    function _deployFlashAndSwapAdapters() internal override {
        mockRouter = new Mock1InchRouter();
        mockVault = new MockBalancer();

        BalancerV3Adapter tempBalancer = new BalancerV3Adapter(address(mockVault));
        balancerAdapter = BalancerV3Adapter(_etchToVanity(address(tempBalancer), FLASH_PREFIX, 99));

        OneInchAdapter tempSwap = new OneInchAdapter(address(mockRouter));
        swapAdapter = OneInchAdapter(_etchToVanity(address(tempSwap), SWAP_PREFIX, 100));
    }

    function setUp() public override {
        super.setUp();
        tokenA = new MockERC20("TokenA", "TKNA");
        tokenB = new MockERC20("TokenB", "TKNB");

        deal(address(tokenA), owner, 1 ether);
        deal(address(tokenA), address(balancerAdapter), 2 ether);

        compoundRewardController = new MockCompoundRewardsController(address(tokenA));
        mockComet = new MockComet();
        mockAavePool = new MockAavePool();
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

    function test_OpenPositionSuccess() public {
        vm.prank(owner);
        tokenA.approve(address(ledero), type(uint256).max);
        OpenPositionParams memory params = _getDefaultOpenPositionParams();
        params.lendingPool = address(mockComet);
        params.swapData = abi.encodeWithSelector(
            Mock1InchRouter.swap.selector, params.borrowToken, params.collateralToken, 2 ether, address(ledero)
        );
        deal(address(tokenA), address(mockVault), 2 ether);
        deal(address(tokenA), address(mockRouter), 2 ether);
        deal(address(tokenB), address(mockComet), 2 ether);

        vm.mockCall(
            params.lendingAdapter,
            abi.encodeWithSelector(ILendingAdapter.getPositionHealthFactor.selector),
            abi.encode(2 ether)
        );

        vm.prank(owner);
        ledero.createLeveragedPosition(params);
    }

    function test_UnwindPositionSuccess() public {
        UnwindPositionParams memory params = _getDefaultUnwindPositionParams();
        params.lendingPool = address(mockComet);
        params.swapData = abi.encodeWithSelector(
            Mock1InchRouter.swap.selector, params.collateralToken, params.debtToken, 1 ether, address(ledero)
        );

        vm.mockCall(
            address(compoundAdapter),
            abi.encodeWithSelector(ILendingAdapter.getPositionHealthFactor.selector),
            abi.encode(2 ether)
        );

        deal(address(tokenA), address(mockVault), 1 ether);
        deal(address(tokenB), address(mockComet), 2 ether);
        deal(address(tokenB), address(ledero), 4 ether);
        deal(address(tokenA), address(mockRouter), 1 ether);

        vm.startPrank(owner);
        ledero.unwindPosition(params);

        vm.stopPrank();
    }

    function test_MigrationSuccess() public {
        MigrationParams memory params = _getDefaultMigrationPositionParams();
        params.minCollateralToSupply = 1 ether;
        params.collateralAmount = 1 ether;
        params.lendingAdapterTo = address(aaveAdapter);
        params.fromPool = address(mockComet);
        params.toPool = address(mockAavePool);

        deal(address(tokenB), address(mockComet), 1 ether);

        vm.mockCall(
            address(aaveAdapter),
            abi.encodeWithSelector(ILendingAdapter.getPositionHealthFactor.selector),
            abi.encode(2 ether)
        );

        vm.prank(owner);
        ledero.migratePosition(params);
    }

    function test_RevertIf_OpenPositionInsufficientSwapReturnForFlashLoan() public {
        vm.prank(owner);
        tokenA.approve(address(ledero), type(uint256).max);
        OpenPositionParams memory params = _getDefaultOpenPositionParams();

        deal(address(tokenA), address(mockVault), 2 ether);

        vm.mockCall(
            params.lendingAdapter,
            abi.encodeWithSelector(ILendingAdapter.supplyAndBorrow.selector),
            abi.encode(new AdapterAction[](0))
        );
        vm.mockCall(
            params.swapAdapter, abi.encodeWithSelector(ISwapAdapter.swap.selector), abi.encode(new AdapterAction[](0))
        );

        vm.mockCall(
            address(tokenA), abi.encodeWithSelector(IERC20.balanceOf.selector, address(ledero)), abi.encode(1 ether)
        );

        vm.expectRevert(abi.encodeWithSelector(InsufficientSwapReturnForFlashLoan.selector, 2 ether, 1 ether));
        vm.prank(owner);
        ledero.createLeveragedPosition(params);
    }

    function test_RevertIf_UnwindPositionUnwindSwapReturnTooLow() public {
        UnwindPositionParams memory params = _getDefaultUnwindPositionParams();
        params.collateralToWithdraw = type(uint256).max;
        params.collateralToken = address(tokenB);
        params.lendingPool = address(mockComet);
        params.minReturnAmount = 1 ether;
        AdapterAction[] memory unwindActions = new AdapterAction[](0);
        vm.mockCall(
            address(compoundAdapter),
            abi.encodeWithSelector(ILendingAdapter.repayAndWithdraw.selector),
            abi.encode(unwindActions)
        );

        AdapterAction[] memory swapActions = new AdapterAction[](0);
        vm.mockCall(address(swapAdapter), abi.encodeWithSelector(ISwapAdapter.swap.selector), abi.encode(swapActions));

        deal(address(tokenA), address(mockVault), 1 ether);

        vm.mockCall(
            address(compoundAdapter),
            abi.encodeWithSelector(
                ILendingAdapter.getPositionHealthFactor.selector, address(mockComet), address(ledero), address(tokenB)
            ),
            abi.encode(1 ether)
        );

        vm.startPrank(owner);

        vm.expectRevert(abi.encodeWithSelector(UnwindSwapReturnTooLow.selector, 1 ether, 0));

        ledero.unwindPosition(params);
        vm.stopPrank();
    }

    function test_RevertIf_UnwindPositionPositionHealthTooLow() public {
        UnwindPositionParams memory params = _getDefaultUnwindPositionParams();
        params.lendingPool = address(456);

        AdapterAction[] memory unwindActions = new AdapterAction[](0);
        vm.mockCall(
            address(compoundAdapter),
            abi.encodeWithSelector(ILendingAdapter.repayAndWithdraw.selector),
            abi.encode(unwindActions)
        );

        AdapterAction[] memory swapActions = new AdapterAction[](0);
        vm.mockCall(address(swapAdapter), abi.encodeWithSelector(ISwapAdapter.swap.selector), abi.encode(swapActions));

        vm.mockCall(
            address(compoundAdapter),
            abi.encodeWithSelector(ILendingAdapter.getPositionHealthFactor.selector),
            abi.encode(1 ether)
        );

        deal(address(tokenA), address(mockVault), 1 ether);
        deal(address(tokenB), address(ledero), 4 ether);

        vm.startPrank(owner);

        vm.expectRevert(abi.encodeWithSelector(PositionHealthTooLow.selector));
        ledero.unwindPosition(params);

        vm.stopPrank();
    }

    // Migration
    function test_RevertIf_MigrationInsufficientCollateralRecovered() public {
        MigrationParams memory params = _getDefaultMigrationPositionParams();
        params.minCollateralToSupply = 10 ether;
        params.collateralAmount = 1 ether;

        AdapterAction[] memory unwindActions = new AdapterAction[](1);
        unwindActions[0] = AdapterAction({
            target: address(params.collateralToken),
            approveToken: address(0),
            approveAmount: 0,
            callData: abi.encodeWithSelector(IERC20.transfer.selector, address(ledero), 1 ether)
        });

        vm.mockCall(
            params.lendingAdapterFrom,
            abi.encodeWithSelector(ILendingAdapter.repayAndWithdraw.selector),
            abi.encode(unwindActions)
        );

        deal(params.collateralToken, address(ledero), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(InsufficientCollateralRecovered.selector, 10 ether, 1 ether));

        vm.prank(owner);
        ledero.migratePosition(params);
    }

    function test_Migration_SendsLeftoversToOwner() public {
        MigrationParams memory params = _getDefaultMigrationPositionParams();

        uint256 totalAvailable = 1.5 ether;
        uint256 amountToUse = 1.0 ether;
        uint256 leftover = 0.5 ether;

        deal(params.collateralToken, address(ledero), totalAvailable);
        deal(params.debtToken, address(ledero), totalAvailable);

        uint256 ownerCollateralBefore = IERC20(params.collateralToken).balanceOf(owner);
        uint256 ownerDebtBefore = IERC20(params.debtToken).balanceOf(owner);

        AdapterAction[] memory unwindActions = new AdapterAction[](1);
        unwindActions[0] = AdapterAction({
            target: address(params.collateralToken),
            approveToken: address(0),
            approveAmount: 0,
            callData: abi.encodeWithSelector(IERC20.transfer.selector, address(0xdead), amountToUse)
        });
        vm.mockCall(
            params.lendingAdapterFrom,
            abi.encodeWithSelector(ILendingAdapter.repayAndWithdraw.selector),
            abi.encode(unwindActions)
        );

        AdapterAction[] memory lendActions = new AdapterAction[](1);
        lendActions[0] = AdapterAction({
            target: address(params.debtToken),
            approveToken: address(0),
            approveAmount: 0,
            callData: abi.encodeWithSelector(IERC20.transfer.selector, address(0xdead), amountToUse)
        });
        vm.mockCall(
            params.lendingAdapterTo,
            abi.encodeWithSelector(ILendingAdapter.supplyAndBorrow.selector),
            abi.encode(lendActions)
        );

        vm.mockCall(
            params.lendingAdapterTo,
            abi.encodeWithSelector(ILendingAdapter.getPositionHealthFactor.selector),
            abi.encode(2 ether)
        );

        // Migration
        vm.prank(owner);
        ledero.migratePosition(params);

        //  leftovers (0.5 ether) transfer to owner
        assertEq(
            IERC20(params.collateralToken).balanceOf(owner),
            ownerCollateralBefore + leftover,
            "Collateral leftovers not sent"
        );
        assertEq(IERC20(params.debtToken).balanceOf(owner), ownerDebtBefore + leftover, "Debt leftovers not sent");

        assertEq(IERC20(params.collateralToken).balanceOf(address(ledero)), 0);
        assertEq(IERC20(params.debtToken).balanceOf(address(ledero)), 0);
    }

    function test_ActionsExecute_ClearsLeftoverAllowance() public {
        vm.prank(owner);
        tokenA.approve(address(ledero), type(uint256).max);

        OpenPositionParams memory params = _getDefaultOpenPositionParams();
        params.lendingPool = address(mockComet);

        params.swapData = abi.encodeWithSelector(
            Mock1InchRouter.swap.selector, params.borrowToken, params.collateralToken, 2 ether, address(ledero)
        );

        deal(address(tokenA), address(mockVault), 2 ether);
        deal(address(tokenA), address(mockRouter), 2 ether);
        deal(address(tokenB), address(mockComet), 2 ether);

        deal(params.collateralToken, address(ledero), 10 ether);

        vm.mockCall(address(mockRouter), params.swapData, abi.encode(true));

        vm.mockCall(
            params.lendingAdapter,
            abi.encodeWithSelector(ILendingAdapter.getPositionHealthFactor.selector),
            abi.encode(2 ether)
        );

        vm.prank(owner);
        ledero.createLeveragedPosition(params);
    }

    // Manual operations

    function test_SupplyCollateral() public {
        deal(address(tokenA), owner, 10 ether);

        vm.startPrank(owner);
        tokenA.approve(address(ledero), 10 ether);

        ledero.supplyCollateral(address(compoundAdapter), address(mockComet), address(tokenA), 10 ether);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(address(ledero)), 0);
        assertEq(tokenA.balanceOf(address(owner)), 0);
        assertEq(tokenA.balanceOf(address(mockComet)), 10 ether);
    }

    function test_RepayDebt() public {
        uint256 repayAmount = 10 ether;

        deal(address(tokenA), owner, repayAmount);

        vm.startPrank(owner);
        tokenA.approve(address(ledero), repayAmount);
        ledero.repayDebt(address(compoundAdapter), address(mockComet), address(tokenA), repayAmount);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(owner), 0, "Owner should have 0 tokens");

        assertEq(tokenA.balanceOf(address(ledero)), 0, "Ledero should not hold tokens");

        assertEq(tokenA.balanceOf(address(mockComet)), repayAmount, "Mock pool should receive repaid tokens");
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

    function test_RevertIf_UnauthorizedCallback() public {
        // By default, transient storage has zero address in expected flashloan adapter
        vm.mockCall(address(0), abi.encodeWithSignature("VAULT()"), abi.encode(address(999)));
        vm.expectRevert(UnauthorizedCallback.selector);
        ledero.receiveFlashLoan(hex"aa");
    }

    function test_BorrowDebt() public {
        uint256 borrowAmount = 5 ether;

        deal(address(tokenB), address(ledero), borrowAmount);

        vm.startPrank(owner);
        vm.mockCall(
            address(123),
            abi.encodeWithSignature("withdraw(address,uint256)", address(tokenB), borrowAmount),
            abi.encode()
        );

        ledero.borrowDebt(address(compoundAdapter), address(123), address(tokenB), borrowAmount);
        vm.stopPrank();

        assertEq(tokenB.balanceOf(owner), borrowAmount);
    }

    // Claim
    function test_ClaimProtocolRewards() public {
        deal(address(tokenA), address(compoundRewardController), 10 ether);

        uint256 balanceBefore = tokenA.balanceOf(owner);
        vm.startPrank(owner);
        ledero.claimProtocolRewards(
            address(compoundAdapter),
            address(123),
            address(tokenA),
            address(tokenB),
            address(compoundRewardController),
            owner
        );
        vm.stopPrank();

        uint256 balanceAfter = tokenA.balanceOf(owner);

        assertEq(balanceAfter - balanceBefore, 10 ether);
    }

    function test_RevertIf_ActionCallFailsWithNoData() public {
        OpenPositionParams memory params = _getDefaultOpenPositionParams();

        AdapterAction[] memory actions = new AdapterAction[](1);
        actions[0] = AdapterAction({
            target: address(balancerAdapter),
            approveToken: address(0),
            approveAmount: 0,
            callData: abi.encodeWithSignature("someFunction()")
        });

        vm.mockCall(
            address(balancerAdapter),
            abi.encodeWithSelector(IFlashLoanAdapter.takeFundsFirstStep.selector),
            abi.encode(actions)
        );

        vm.mockCallRevert(
            address(balancerAdapter),
            abi.encodeWithSignature("someFunction()"),
            bytes("") // empty respomse
        );

        deal(params.collateralToken, address(ledero), 2 ether);

        vm.startPrank(owner);
        IERC20(params.collateralToken).approve(address(ledero), 2 ether);

        vm.expectRevert(ActionExecutionFailed.selector);

        ledero.createLeveragedPosition(params);
        vm.stopPrank();
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
