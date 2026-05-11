// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {CompoundV3Adapter} from "../../src/adapters/lendings/CompoundV3.sol";
import {IComet} from "../../src/interfaces/external/ICompound.sol";
import {ConstantsEtMainnet} from "../Constants.t.sol";

contract CompoundAdapterTest is Test, ConstantsEtMainnet {
    CompoundV3Adapter compoundAdapter;
    address user = makeAddr("user");

    function setUp() public {
        compoundAdapter = new CompoundV3Adapter();
    }

    function test_Version() public {
        uint256 adapterVersion = compoundAdapter.getVersion();
        assertEq(adapterVersion, 1);
    }

    function test_CompoundAdapter_HealthFactor_DustDebt() public {
        vm.mockCall(
            COMPOUND_WETH_COMET,
            abi.encodeWithSelector(IComet.borrowBalanceOf.selector, user),
            abi.encode(1) // 1 wei
        );

        uint256 health = compoundAdapter.getPositionHealthFactor(COMPOUND_WETH_COMET, user, address(USDC));

        assertEq(health, type(uint256).max, "Health should be max for dust debt");
    }
}
