// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

contract MockRevertAll {
    error AdapterIsDead();

    fallback() external payable {
        revert AdapterIsDead();
    }

    receive() external payable {
        revert AdapterIsDead();
    }
}
