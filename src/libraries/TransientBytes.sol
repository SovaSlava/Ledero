// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

library TransientBytes {
    function tstore(bytes32 slot, bytes memory data) internal {
        assembly {
            let length := mload(data)
            tstore(slot, length)

            let words := div(add(length, 31), 32)

            let dataPtr := add(data, 0x20)

            for { let i := 0 } lt(i, words) { i := add(i, 1) } {
                let targetSlot := add(slot, add(i, 1))
                let word := mload(dataPtr)
                tstore(targetSlot, word)
                dataPtr := add(dataPtr, 0x20)
            }
        }
    }

    function tload(bytes32 slot) internal view returns (bytes memory data) {
        assembly {
            let length := tload(slot)

            data := mload(0x40)
            mstore(data, length)

            let words := div(add(length, 31), 32)
            let dataPtr := add(data, 0x20)

            for { let i := 0 } lt(i, words) { i := add(i, 1) } {
                let targetSlot := add(slot, add(i, 1))
                let word := tload(targetSlot)
                mstore(dataPtr, word)
                dataPtr := add(dataPtr, 0x20)
            }

            mstore(0x40, add(data, add(0x20, mul(words, 0x20))))
        }
    }
}
