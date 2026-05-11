// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILedero} from "../../src/interfaces/ILedero.sol";

contract MockBalancer {
    using SafeERC20 for IERC20;

    uint256 public flashLoanFeeBps = 0;

    function setFee(uint256 _feeBps) external {
        flashLoanFeeBps = _feeBps;
    }

    function getFlashLoanFee(
        address,
        /*token*/
        uint256 amount
    )
        public
        view
        returns (uint256)
    {
        return (amount * flashLoanFeeBps) / 10000;
    }

    function unlock(bytes calldata data) external {
        (bool success, bytes memory returnData) = msg.sender.call(data);
        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    let returndata_size := mload(returnData)
                    revert(add(32, returnData), returndata_size)
                }
            } else {
                revert("MockVault: Callback failed");
            }
        }
    }

    function sendTo(address token, address to, uint256 amount) external {
        IERC20(token).safeTransfer(to, amount);
    }

    function settle(address token, uint256 amount) external {
        // IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    function getFullRepayAmount(address token, uint256 amount) external view returns (uint256) {
        return amount + getFlashLoanFee(token, amount);
    }
}
