// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {LederoBase} from "../base/LederoBase.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FfiHelper} from "../helpers/FfiHelper.t.sol";

contract EnvironmentSanityTest is LederoBase, FfiHelper {
    function test_USDCTokenExists() public view {
        uint256 totalSupply = IERC20(USDC).totalSupply();
        assertTrue(
            totalSupply > 0, "Environment Error: USDC total supply is 0. Fork might be broken or USDC address is wrong."
        );
    }

    function test_FFI_Get1inchSwapData() public {
        uint256 swapAmount = 1000e6; // 1000 USDC

        (bytes memory swapData, uint256 expectedAmount) =
            get1inchSwapData(address(USDC), address(WETH), swapAmount, address(ledero));

        assertTrue(swapData.length > 0, "Environment Error: Failed to get swap data from 1inch API");
        assertTrue(expectedAmount > 0, "Environment Error: 1inch API returned 0 expected amount");
    }
}
