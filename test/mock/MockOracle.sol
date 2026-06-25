// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

contract MockOracle {
    function getPrice(address) external pure returns (uint256) {
        return 3000e8;
    }
}
