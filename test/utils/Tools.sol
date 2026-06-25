// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

abstract contract Tools is Test {
    function _etchToVanity(address originalAddress, uint8 prefix, uint160 salt) internal returns (address) {
        uint160 vanityNum = (uint160(prefix) << 140) | salt;
        address vanityAddr = address(vanityNum);

        vm.etch(vanityAddr, originalAddress.code);

        return vanityAddr;
    }
}
