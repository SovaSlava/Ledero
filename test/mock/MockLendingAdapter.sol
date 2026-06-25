// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

contract MockLendingAdapter {
    error PoolIsZero();

    function getLtv(address, address) external pure returns (uint256) {
        return 8000;
    }

    function getDebtAmount(address, address user, address) external pure returns (uint256) {
        if (user == address(0xDEAD)) return 0;
        return 2280e6;
    }

    function supplyAndBorrow(address pool, address, uint256, address, uint256) external pure {
        require(pool != address(0), PoolIsZero());
    }

    function repayAndWithdraw(address pool, address, uint256, address, uint256) external pure {
        require(pool != address(0), PoolIsZero());
    }
}
