// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {ISwapAdapter} from "../../interfaces/internal/ISwapAdapter.sol";
import {AdapterAction} from "../../interfaces/internal/ILederoTypes.sol";

contract OneInchAdapter is ISwapAdapter {
    address public immutable ROUTER;

    constructor(address _router) {
        ROUTER = _router;
    }

    function swap(address tokenIn, uint256 amountIn, bytes calldata payload)
        external
        view
        override
        returns (AdapterAction[] memory actions)
    {
        actions = new AdapterAction[](1);

        actions[0] = AdapterAction({target: ROUTER, approveToken: tokenIn, approveAmount: amountIn, callData: payload});
    }

    function getVersion() external pure returns (uint256) {
        return 1;
    }
}
