// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {AggregatorV3Interface} from "./interfaces/external/AggregatorV3Interface.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title LederoOracle
 * @notice Works with Chainlink price feeds.
 */
contract LederoOracle is Ownable2Step {
    mapping(address token => address priceFeed) public priceFeeds;
    mapping(address token => uint256 heartBeat) public tokenHeartbeats;

    error IncorrectLength();
    error UnsupportDecimals();
    error PriceFeedNotSet();
    error HeartbeatNotSet();
    error InvalidPrice();
    error RoundIncomplete();
    error StaleRound();
    error StalePrice();
    event PriceFeedUpdated(address indexed token, address indexed priceFeed, uint256 heartbeat);

    constructor() Ownable(msg.sender) {}

    function setPriceFeed(address _token, address _priceFeed, uint256 _heartbeat) external onlyOwner {
        _setPriceFeed(_token, _priceFeed, _heartbeat);
    }

    function setPriceFeeds(address[] calldata _tokens, address[] calldata _priceFeeds, uint256[] calldata _heartbeats)
        external
        onlyOwner
    {
        require(_tokens.length == _priceFeeds.length && _tokens.length == _heartbeats.length, IncorrectLength());

        for (uint256 i; i < _tokens.length; i++) {
            _setPriceFeed(_tokens[i], _priceFeeds[i], _heartbeats[i]);
        }
    }

    function _setPriceFeed(address _token, address _priceFeed, uint256 _heartbeat) internal {
        uint8 decimals = AggregatorV3Interface(_priceFeed).decimals();
        require(decimals == 8, UnsupportDecimals());

        priceFeeds[_token] = _priceFeed;
        tokenHeartbeats[_token] = _heartbeat;

        emit PriceFeedUpdated(_token, _priceFeed, _heartbeat);
    }

    function getPrice(address _token) public view returns (uint256 price) {
        address priceFeedAddress = priceFeeds[_token];
        require(priceFeedAddress != address(0), PriceFeedNotSet());

        uint256 maxStaleness = tokenHeartbeats[_token];
        require(maxStaleness != 0, HeartbeatNotSet());

        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) =
            AggregatorV3Interface(priceFeedAddress).latestRoundData();

        require(answer > 0, InvalidPrice());
        require(updatedAt != 0, RoundIncomplete());
        require(answeredInRound >= roundId, StaleRound());
        require(block.timestamp - updatedAt < maxStaleness, StalePrice());

        return uint256(answer);
    }
}
