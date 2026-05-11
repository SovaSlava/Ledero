// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

abstract contract FfiHelper is Test {
    function get1inchSwapData(address fromToken, address toToken, uint256 amount, address fromAddress)
        internal
        returns (bytes memory swapData, uint256 expectedAmount)
    {
        // node test/scripts/get_1inch_data.ts <from> <to> <amount> <address>
        string[] memory inputs = new string[](7);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "test/scripts/get_1inch_data.ts";
        inputs[3] = vm.toString(fromToken);
        inputs[4] = vm.toString(toToken);
        inputs[5] = vm.toString(amount);
        inputs[6] = vm.toString(fromAddress);

        bytes memory result = vm.ffi(inputs);
        string memory jsonResponse = string(result);

        // Check error
        bytes memory errorCheck = vm.parseJson(jsonResponse, ".error");
        if (errorCheck.length > 0) {
            string memory errorMsg = abi.decode(errorCheck, (string));
            revert(string.concat("1inch API Error: ", errorMsg));
        }

        // Parse response
        // https://business.1inch.com/portal/documentation/apis/swap/classic-swap/methods/v6.1/1/swap/method/get
        bytes memory dataBytes = vm.parseJson(jsonResponse, ".tx.data");
        swapData = abi.decode(dataBytes, (bytes));

        bytes memory toAmountBytes = vm.parseJson(jsonResponse, ".toAmount");
        expectedAmount = abi.decode(toAmountBytes, (uint256));

        return (swapData, expectedAmount);
    }
}
