// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {CompoundV3Adapter} from "../../src/adapters/lendings/CompoundV3.sol";
import {IComet} from "../../src/interfaces/external/ICompound.sol";
import {ConstantsEtMainnet} from "../Constants.t.sol";
import {MockCompoundRewardsController} from "../mock/MockCompoundRewardsController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ledero} from "../../src/Ledero.sol";
import {Tools} from "../utils/Tools.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import "../../src/interfaces/internal/IConstants.sol";

contract CompoundAdapterTest is Test, ConstantsEtMainnet, Tools{
    CompoundV3Adapter compoundAdapter;
    address public owner = makeAddr("owner");
    Ledero public ledero; // pure implementation without proxy
    MockERC20 public mockERC20;

    function setUp() public {
        vm.startPrank(owner);
        ledero = new Ledero();
        ledero.initialize();
        vm.stopPrank();
        CompoundV3Adapter tempCompound = new CompoundV3Adapter();
        compoundAdapter = CompoundV3Adapter(_etchToVanity(address(tempCompound), LENDING_PREFIX, 1));
        mockERC20 = new MockERC20("AAVE", "aave");
        vm.etch(COMP_TOKEN, address(mockERC20).code);
    }

    function test_Version() public {
        uint256 adapterVersion = compoundAdapter.getVersion();
        assertEq(adapterVersion, 1);
    }

    function test_claimProtocolRewards_CompoundV3_Success() public {
        address cometPool = address(0x3333);

        MockCompoundRewardsController mockController = new MockCompoundRewardsController(COMP_TOKEN);

        deal(COMP_TOKEN, address(mockController), 1000 * 10 ** 18);

        uint256 balanceBefore = IERC20(COMP_TOKEN).balanceOf(owner);

        vm.prank(owner);

        ledero.claimProtocolRewards(
            address(compoundAdapter), cometPool, address(USDC), address(WBTC), address(mockController), owner
        );

        uint256 balanceAfter = IERC20(COMP_TOKEN).balanceOf(owner);
        uint256 earnedRewards = balanceAfter - balanceBefore;

        assertEq(earnedRewards, 30e18, "Compound Rewards transfer failed");
    }


    function test_CompoundAdapter_HealthFactor_DustDebt() public {

        // debt 1 wei
        vm.mockCall(
            COMPOUND_USDC_COMET,
            abi.encodeWithSelector(IComet.borrowBalanceOf.selector, owner),
            abi.encode(1) // 1 wei
        );

        // mock feed
        address mockFeed = address(0x123);
        vm.mockCall(
            COMPOUND_USDC_COMET,
            abi.encodeWithSelector(IComet.baseTokenPriceFeed.selector),
            abi.encode(mockFeed)
        );

        // mock price 2000$
        vm.mockCall(
            COMPOUND_USDC_COMET,
            abi.encodeWithSelector(IComet.getPrice.selector, mockFeed),
            abi.encode(2000e8) 
        );

        // mock scale
        vm.mockCall(
            COMPOUND_USDC_COMET,
            abi.encodeWithSelector(IComet.baseScale.selector),
        abi.encode(1e18) 
        );
        
        uint256 health = compoundAdapter.getPositionHealthFactor(COMPOUND_USDC_COMET, owner, address(USDC));

        assertEq(health, type(uint256).max, "Health should be max for dust debt");
    }
}
