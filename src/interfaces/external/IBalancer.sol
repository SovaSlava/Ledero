// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

interface IBalancerVault {
    function unlock(bytes calldata data) external returns (bytes memory);
    function sendTo(address token, address to, uint256 amount) external;
    function settle(address token, uint256 amount) external;
}

interface IBalancerVaultUnlockAware {
    function receiveVaultUnlock(bytes calldata data) external returns (bytes memory);
}
