// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

abstract contract Constants {
    // solhint-disable private-vars-leading-underscore
    uint8 internal constant LENDING_PREFIX = 0x1;
    uint8 internal constant FLASH_PREFIX = 0x2;
    uint8 internal constant SWAP_PREFIX = 0x3;
    uint256 internal constant PREFIX_SHIFT = 140;
    uint256 internal constant MIN_SAFE_HF = 1.05e18;
    // solhint-enable private-vars-leading-underscore
}
