// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AdapterAction} from "../interfaces/internal/ILederoTypes.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILederoErrors} from "../interfaces/internal/ILederoErrors.sol";

abstract contract ActionExecutor is ILederoErrors {
    using SafeERC20 for IERC20;

    bytes4 internal constant _ACTION_FAILED_SELECTOR = 0x8ec18720;

    function _executeActions(AdapterAction[] memory actions) internal {
        uint256 len = actions.length;
        for (uint256 i; i < len;) {
            AdapterAction memory act = actions[i];

            address target = act.target;
            address approveToken = act.approveToken;
            bool needsApprove = act.approveAmount > 0;

            if (needsApprove) {
                IERC20(approveToken).forceApprove(target, act.approveAmount);
            }

            // solhint-disable-next-line avoid-low-level-calls
            (bool success,) = target.call(act.callData);

            if (!success) {
                assembly ("memory-safe") {
                    let size := returndatasize()

                    if iszero(size) {
                        mstore(0x00, _ACTION_FAILED_SELECTOR)
                        revert(0x00, 0x04)
                    }
                    let ptr := mload(0x40)
                    returndatacopy(ptr, 0, size)
                    revert(ptr, size)
                }
            }

            if (needsApprove) {
                uint256 leftoverAllowance = IERC20(approveToken).allowance(address(this), target);
                if (leftoverAllowance > 0) {
                    IERC20(approveToken).forceApprove(target, 0);
                }
            }

            unchecked {
                ++i;
            }
        }
    }
}
