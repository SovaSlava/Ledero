// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

interface ILederoOracle {
    /// @param token Token address
    /// @param priceFeed Chainlink price feed address
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);

    function setPriceFeed(address _token, address _priceFeed) external;

    function setPriceFeeds(address[] calldata _tokens, address[] calldata _priceFeeds) external;

    function getPrice(address _token) external view returns (uint256 price);

    function getPriceDecimals(address _token) external view returns (uint8 decimals);

    function getRoundData(address _token)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function priceFeeds(address _token) external view returns (address);
}
