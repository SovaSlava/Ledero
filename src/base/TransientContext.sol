// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;
import {Operation} from "../interfaces/internal/ILederoTypes.sol";

abstract contract TransientContext {
    // keccak256(abi.encode(uint256(keccak256("ledero.storage.transient.context")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 private constant _CONTEXT_SLOT = 0x1f02c6426cf03e83b8bd111da9cf7149021611cbe2ba19e8ee4a273e04e03700;

    function _setTransientContext(address adapter, Operation op) internal {
        assembly ("memory-safe") {
            // [op][adapter]
            let packed := or(adapter, shl(160, op))
            tstore(_CONTEXT_SLOT, packed)
        }
    }

    function _clearTransientContext() internal {
        assembly ("memory-safe") {
            tstore(_CONTEXT_SLOT, 0)
        }
    }

    function _getTransientContext() internal view returns (address adapter, Operation op) {
        assembly ("memory-safe") {
            let packed := tload(_CONTEXT_SLOT)

            // extract address
            adapter := and(packed, 0xffffffffffffffffffffffffffffffffffffffff)

            // extract op
            op := shr(160, packed)
        }
    }
}
