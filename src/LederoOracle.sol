// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IAggregatorV3Interface} from "./interfaces/external/IAggregatorV3Interface.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ILederoErrors} from "./interfaces/internal/ILederoErrors.sol";

/**
 * @title LederoOracle
 * @notice Works with Chainlink price feeds.
 */
contract LederoOracle is Ownable2Step, ILederoErrors {
    using SafeCast for int256;

    mapping(address token => address priceFeed) public priceFeeds;
    mapping(address token => uint256 heartBeat) public tokenHeartbeats;

    constructor() Ownable(msg.sender) {}

    function setPriceFeed(address _token, address _priceFeed, uint256 _heartbeat) external onlyOwner {
        _setPriceFeed(_token, _priceFeed, _heartbeat);
    }

    function setPriceFeeds(address[] calldata _tokens, address[] calldata _priceFeeds, uint256[] calldata _heartbeats)
        external
        onlyOwner
    {
        if (_tokens.length != _priceFeeds.length || _tokens.length != _heartbeats.length) revert IncorrectLength();

        uint256 tokensLength = _tokens.length;
        for (uint256 i; i < tokensLength;) {
            _setPriceFeed(_tokens[i], _priceFeeds[i], _heartbeats[i]);
            unchecked {
                i++;
            }
        }
    }

    function _setPriceFeed(address _token, address _priceFeed, uint256 _heartbeat) internal {
        uint8 decimals = IAggregatorV3Interface(_priceFeed).decimals();
        if (decimals != 8) revert UnsupportDecimals();

        priceFeeds[_token] = _priceFeed;
        tokenHeartbeats[_token] = _heartbeat;

        emit PriceFeedUpdated(_token, _priceFeed, _heartbeat);
    }

    function getPrice(address _token) public view returns (uint256 price) {
        address priceFeedAddress = priceFeeds[_token];
        if (priceFeedAddress == address(0)) revert PriceFeedNotSet();

        uint256 maxStaleness = tokenHeartbeats[_token];
        if (maxStaleness == 0) revert HeartbeatNotSet();

        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) =
            IAggregatorV3Interface(priceFeedAddress).latestRoundData();

        if (answer <= 0) revert InvalidPrice();
        if (updatedAt == 0) revert RoundIncomplete();
        if (answeredInRound < roundId) revert StaleRound();
        if (block.timestamp - updatedAt > maxStaleness) revert StalePrice();

        return answer.toUint256();
    }
}
