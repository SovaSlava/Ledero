// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {AaveV3Adapter} from "../../src/adapters/lendings/AaveV3.sol";

contract AaveV3AdapterTest is Test {
    AaveV3Adapter aaveAdapter;

    function setUp() public {
        aaveAdapter = new AaveV3Adapter();
    }

    function test_Version() public {
        uint256 adapterVersion = aaveAdapter.getVersion();
        assertEq(adapterVersion, 1);
    }
}
