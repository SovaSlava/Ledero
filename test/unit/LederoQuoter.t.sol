// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {LederoQuoter} from "../../src/LederoQuoter.sol";
import {LederoOracle} from "../../src/LederoOracle.sol";
import {MockLendingAdapter} from "../mock/MockLendingAdapter.sol";
import {MockBalancer} from "../mock/MockBalancer.sol";
import {MockOracle} from "../mock/MockOracle.sol";

contract MockToken {
    uint8 public decimals;

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }
}

contract LederoQuoterTest is Test {
    LederoQuoter quoter;
    MockLendingAdapter lendingAdapter;
    MockBalancer flashAdapter;
    MockToken wbtc;
    MockToken usdc;
    address dummyPool = address(0x111);

    function setUp() public {
        MockOracle oracle = new MockOracle();
        quoter = new LederoQuoter(address(oracle));

        lendingAdapter = new MockLendingAdapter();
        flashAdapter = new MockBalancer();
        wbtc = new MockToken(18);
        usdc = new MockToken(6);
    }

    function test_CalculateOpenParams_UsesOracleWhenPricesAreZero() public view {
        LederoQuoter.QuoteOpenParams memory params = LederoQuoter.QuoteOpenParams({
            lendingAdapter: address(lendingAdapter),
            flashAdapter: address(flashAdapter),
            lendingPool: dummyPool,
            collateralToken: address(usdc),
            borrowToken: address(wbtc),
            desiredLeverage: 30000,
            collateralAmount: 100e6,
            collateralTokenPrice: 0,
            borrowTokenPrice: 0
        });

        (uint256 flash, uint256 borrow,) = quoter.calculateOpenParams(params);
        assertTrue(flash > 0 && borrow > 0);
    }

    function test_CalculateUnwindParams_ReturnsZeroIfNoDebt() public view {
        LederoQuoter.QuoteUnwindParams memory params = LederoQuoter.QuoteUnwindParams({
            lendingAdapter: address(lendingAdapter),
            flashAdapter: address(flashAdapter),
            lendingPool: dummyPool,
            collateralToken: address(usdc),
            debtToken: address(wbtc),
            user: address(0xDEAD), // return 0
            slippageBps: 100
        });

        (uint256 colToWithdraw, uint256 debtToRepay, uint256 flashRepay) = quoter.calculateUnwindParams(params);

        assertEq(colToWithdraw, 0);
        assertEq(debtToRepay, 0);
        assertEq(flashRepay, 0);
    }

    function test_GetMaxLeverage() public view {
        uint256 expectedMaxLeverage = 41666;

        uint256 actualMaxLeverage = quoter.getMaxLeverage(address(lendingAdapter), dummyPool, address(usdc));

        assertEq(actualMaxLeverage, expectedMaxLeverage, "Max leverage mismatch in Quoter");
    }

    function test_RevertIf_TokenHasNoDecimals() public {
        address badToken = address(new MockBalancer()); // no erc20 contract

        LederoQuoter.QuoteOpenParams memory params = LederoQuoter.QuoteOpenParams({
            lendingAdapter: address(lendingAdapter),
            flashAdapter: address(flashAdapter),
            lendingPool: dummyPool,
            collateralToken: badToken,
            borrowToken: address(wbtc),
            desiredLeverage: 30000,
            collateralAmount: 100e6,
            collateralTokenPrice: 1e8,
            borrowTokenPrice: 1e8
        });

        vm.expectRevert(LederoQuoter.NoDecimals.selector);
        quoter.calculateOpenParams(params);
    }
}
