// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

contract MockPriceFeed {
    int256 public answer;

    uint256 public forcedUpdatedAt;
    bool public isTimestampForced;
    uint8 public decimals = 8;
    uint80 public mockRoundId = 1;
    uint80 public mockAnsweredInRound = 1;

    constructor(int256 _answer) {
        answer = _answer;
    }

    function setDecimals(uint8 _decimals) external {
        decimals = _decimals;
    }

    function setAnswer(int256 _answer) external {
        answer = _answer;
    }

    function setRoundIds(uint80 _roundId, uint80 _answeredInRound) external {
        mockRoundId = _roundId;
        mockAnsweredInRound = _answeredInRound;
    }

    function setRoundData(int256 _answer, uint256 _updatedAt) external {
        answer = _answer;
        forcedUpdatedAt = _updatedAt;
        isTimestampForced = true;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 _answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        uint256 timestampToUse = isTimestampForced ? forcedUpdatedAt : block.timestamp;
        return (mockRoundId, answer, timestampToUse, timestampToUse, mockAnsweredInRound);
    }
}
