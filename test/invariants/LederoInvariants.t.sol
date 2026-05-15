// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {LederoBase} from "../base/LederoBase.t.sol";
import {LederoHandler, IOracleRefresher} from "./LederoHandler.t.sol";
import {Mock1InchRouter} from "../mock/Mock1InchRouter.sol";
import {MockBalancer} from "../mock/MockBalancer.sol";
import {BalancerV3Adapter} from "../../src/adapters/loan/BalancerV3.sol";
import {OneInchAdapter} from "../../src/adapters/swap/OneInch.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../src/interfaces/internal/IConstants.sol";
import {AggregatorV3Interface} from "../../src/interfaces/external/AggregatorV3Interface.sol";

contract LederoInvariantsTest is LederoBase {
    LederoHandler public handler;
    Mock1InchRouter public mockRouter;
    MockBalancer public mockVault;
    int256 public usdcPrice;
    int256 public wbtcPrice;

    function _deployOracle() internal override {
        super._deployOracle();
        (, usdcPrice,,,) = AggregatorV3Interface(USDC_PRICE_FEED).latestRoundData();
        (, wbtcPrice,,,) = AggregatorV3Interface(WBTC_PRICE_FEED).latestRoundData();
        _refreshOracleMocks();
    }

    function _deployFlashAndSwapAdapters() internal override {
        // 1. Деплоим моки вместо того, чтобы брать адреса из мейннета
        mockRouter = new Mock1InchRouter();
        mockVault = new MockBalancer();

        // 2. Деплоим адаптеры, натравливая их на моки
        BalancerV3Adapter tempBalancer = new BalancerV3Adapter(address(mockVault), address(ledero));
        balancerAdapter = BalancerV3Adapter(_etchToVanity(address(tempBalancer), FLASH_PREFIX, 99));

        OneInchAdapter tempSwap = new OneInchAdapter(address(mockRouter), address(ledero));
        swapAdapter = OneInchAdapter(_etchToVanity(address(tempSwap), SWAP_PREFIX, 100));

        deal(address(USDC), address(mockRouter), 100_000_000e6);
        deal(address(WBTC), address(mockRouter), 10_000e18);
        deal(address(USDC), address(mockVault), 100_000_000e6);
        deal(address(WBTC), address(mockVault), 10_000e18);
    }

    function _refreshOracleMocks() public {
        vm.mockCall(
            USDC_PRICE_FEED,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(uint80(1), usdcPrice, block.timestamp, block.timestamp, uint80(1))
        );

        vm.mockCall(
            WBTC_PRICE_FEED,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(uint80(1), wbtcPrice, block.timestamp, block.timestamp, uint80(1))
        );
    }

    function setUp() public override {
        super.setUp();

        handler = new LederoHandler(
            ledero,
            aaveAdapter,
            compoundAdapter,
            balancerAdapter,
            swapAdapter,
            oracle,
            quoter,
            IOracleRefresher(address(this))
        );

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.userAction_openPositionAave.selector;
        selectors[1] = handler.userAction_unwindPositionAave.selector;
        selectors[2] = handler.userAction_openPositionCompound.selector;
        selectors[3] = handler.userAction_unwindPositionCompound.selector;
        selectors[4] = handler.systemAction_warpTime.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_ClosedPositionMeansZeroDebt() public view {
        if (!handler.isPositionOpen()) {
            uint256 aaveDebt = aaveAdapter.getDebtAmount(AAVE_POOL, address(ledero), address(WBTC));
            uint256 compDebt = compoundAdapter.getDebtAmount(COMPOUND_USDC_COMET, address(ledero), address(WBTC));

            assertEq(aaveDebt + compDebt, 0, "CRITICAL: Debt exists in pools but handler state is closed");
        }
    }

    function invariant_DebtIsIsolatedToOneProtocol() public view {
        uint256 aaveDebt = aaveAdapter.getDebtAmount(AAVE_POOL, address(ledero), address(WBTC));
        uint256 compDebt = compoundAdapter.getDebtAmount(COMPOUND_USDC_COMET, address(ledero), address(WBTC));

        bool isIsolated = (aaveDebt == 0) || (compDebt == 0);

        assertTrue(isIsolated, "Architecture breach: Simultaneous debt in multiple pools");
    }

    function invariant_SystemDustIsStrictlyZero() public view {
        address[5] memory systemContracts = [
            address(ledero),
            address(aaveAdapter),
            address(compoundAdapter),
            address(balancerAdapter),
            address(swapAdapter)
        ];

        for (uint256 i = 0; i < systemContracts.length; i++) {
            uint256 tolerance = systemContracts[i] == address(ledero) ? 2 : 0;

            assertApproxEqAbs(
                IERC20(address(USDC)).balanceOf(systemContracts[i]), 0, tolerance, "USDC leaked into system contract"
            );

            assertApproxEqAbs(
                IERC20(address(WBTC)).balanceOf(systemContracts[i]), 0, tolerance, "WBTC leaked into system contract"
            );
        }
    }

    function invariant_healthFactorIsSafe() public view {
        uint256 MIN_SAFE_HF = 1.05e18; // 1.05
        uint256 hfAave = aaveAdapter.getPositionHealthFactor(AAVE_POOL, address(ledero), address(USDC));
        assertTrue(hfAave == type(uint256).max || hfAave >= MIN_SAFE_HF, "Aave Health Factor dropped below safe limit!");

        uint256 hfCompound =
            compoundAdapter.getPositionHealthFactor(COMPOUND_USDC_COMET, address(ledero), address(USDC));
        assertTrue(
            hfCompound == type(uint256).max || hfCompound >= MIN_SAFE_HF,
            "Compound Health Factor dropped below safe limit!"
        );
    }
}
