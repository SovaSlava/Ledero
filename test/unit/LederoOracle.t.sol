// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {MockPriceFeed} from "../mock/MockPriceFeed.sol";
import {Test} from "forge-std/Test.sol";
import {LederoOracle} from "../../src/LederoOracle.sol";

contract LederoOracleTest is Test {
    LederoOracle oracle;
    MockPriceFeed mockPriceFeed;

    address wbtc = address(0x111);

    function setUp() public {
        oracle = new LederoOracle();

        mockPriceFeed = new MockPriceFeed(80_000e8);
        oracle.setPriceFeed(wbtc, address(mockPriceFeed), 3600);
    }

    function test_GetPrice() public {
        mockPriceFeed.setRoundData(80_000e8, block.timestamp);

        uint256 currentPrice = oracle.getPrice(wbtc);
        assertEq(currentPrice, 80_000e8);
    }

    function test_SetPriceFeeds() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(0x111); // WBTC mock address
        tokens[1] = address(0x222); // USDC mock address

        address[] memory feeds = new address[](2);
        feeds[0] = address(mockPriceFeed);
        MockPriceFeed mockPriceFeed2 = new MockPriceFeed(80_000e8);
        feeds[1] = address(mockPriceFeed2);

        uint256[] memory heartbeats = new uint256[](2);
        heartbeats[0] = 3600;
        heartbeats[1] = 86400;

        oracle.setPriceFeeds(tokens, feeds, heartbeats);

        uint256 currentPrice = oracle.getPrice(tokens[0]);
        assertEq(currentPrice, 80_000e8);
    }

    function test_RevertIf_PriceIsZeroOrNegative() public {
        mockPriceFeed.setRoundData(-100, block.timestamp);

        vm.expectRevert(LederoOracle.InvalidPrice.selector);
        oracle.getPrice(wbtc);

        mockPriceFeed.setRoundData(0, block.timestamp);
        vm.expectRevert(LederoOracle.InvalidPrice.selector);
        oracle.getPrice(wbtc);
    }

    function test_RevertIf_StalePrice() public {
        vm.warp(100 days);
        uint256 oldTimestamp = block.timestamp - 2 days;
        mockPriceFeed.setRoundData(80_000e8, oldTimestamp);
        vm.expectRevert(LederoOracle.StalePrice.selector);
        oracle.getPrice(wbtc);
    }

    function test_RevertIf_IncompleteRound() public {
        mockPriceFeed.setRoundData(80_000e8, 0);
        vm.expectRevert(LederoOracle.RoundIncomplete.selector);
        oracle.getPrice(wbtc);
    }

    function test_RevertIf_SourceNotSet() public {
        address randomToken = address(0xDEAD);
        vm.expectRevert(LederoOracle.PriceFeedNotSet.selector);
        oracle.getPrice(randomToken);
    }

    function test_RevertIf_MaxStaleNotSet() public {
        address randomToken = address(0xDEAD);
        oracle.setPriceFeed(randomToken, address(mockPriceFeed), 0);
        vm.expectRevert(LederoOracle.HeartbeatNotSet.selector);
        oracle.getPrice(randomToken);
    }

    function test_RevertIf_DecimalsIsNot8() public {
        mockPriceFeed.setDecimals(20);
        vm.expectRevert(LederoOracle.UnsupportDecimals.selector);
        oracle.setPriceFeed(wbtc, address(mockPriceFeed), 3600);
    }

    function test_RevertIf_StaleRound() public {
        mockPriceFeed.setRoundIds(2, 1);

        vm.expectRevert(LederoOracle.StaleRound.selector);
        oracle.getPrice(wbtc);
    }

    function test_RevertIf_SetPriceFeeds_IncorrectLength() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(0x111);
        tokens[1] = address(0x222);

        address[] memory shortFeeds = new address[](1);
        shortFeeds[0] = address(mockPriceFeed);

        uint256[] memory validHeartbeats = new uint256[](2);

        vm.expectRevert(LederoOracle.IncorrectLength.selector);
        oracle.setPriceFeeds(tokens, shortFeeds, validHeartbeats);

        address[] memory validFeeds = new address[](2);
        uint256[] memory shortHeartbeats = new uint256[](1);

        vm.expectRevert(LederoOracle.IncorrectLength.selector);
        oracle.setPriceFeeds(tokens, validFeeds, shortHeartbeats);
    }
}
