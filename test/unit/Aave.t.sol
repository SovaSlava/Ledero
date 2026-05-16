// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {AaveV3Adapter} from "../../src/adapters/lendings/AaveV3.sol";
import {MockAaveRewardsController} from "../mock/MockAaveRewardsController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ConstantsEtMainnet} from "../Constants.t.sol";
import {Ledero} from "../../src/Ledero.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {Tools} from "../utils/Tools.sol";
import {IAaveV3Pool} from "../../src/interfaces/external/IAaveV3Pool.sol";
import "../../src/interfaces/internal/IConstants.sol";

contract AaveV3AdapterTest is Test, ConstantsEtMainnet, Tools {
    AaveV3Adapter aaveAdapter;
    address public owner = makeAddr("owner");
    Ledero public ledero; // pure implementation without proxy
    MockERC20 public mockERC20;

    function setUp() public {
        AaveV3Adapter tempAave = new AaveV3Adapter();
        aaveAdapter = AaveV3Adapter(_etchToVanity(address(tempAave), LENDING_PREFIX, 1));
        vm.startPrank(owner);
        ledero = new Ledero();
        ledero.initialize();
        vm.stopPrank();
        mockERC20 = new MockERC20("AAVE", "aave");
        vm.etch(AAVE_TOKEN, address(mockERC20).code);
    }

    function test_Version() public {
        uint256 adapterVersion = aaveAdapter.getVersion();
        assertEq(adapterVersion, 1);
    }

    function test_claimProtocolRewards_AaveV3_Success() public {
        MockAaveRewardsController mockController = new MockAaveRewardsController(AAVE_TOKEN);


        deal(AAVE_TOKEN, address(mockController), 50 ether);

        IAaveV3Pool.ReserveData memory mockColReserve;
        mockColReserve.aTokenAddress = address(111); // aToken

        IAaveV3Pool.ReserveData memory mockDebtReserve;
        mockDebtReserve.variableDebtTokenAddress = address(222); // vToken

        vm.mockCall(
            AAVE_POOL,
            abi.encodeWithSelector(IAaveV3Pool.getReserveData.selector, address(USDC)),
            abi.encode(mockColReserve)
        );

        vm.mockCall(
            AAVE_POOL,
            abi.encodeWithSelector(IAaveV3Pool.getReserveData.selector, address(WBTC)),
            abi.encode(mockDebtReserve)
        );


        uint256 balanceBefore = IERC20(AAVE_TOKEN).balanceOf(owner);

        vm.prank(owner);
        ledero.claimProtocolRewards(
            address(aaveAdapter), AAVE_POOL, address(USDC), address(WBTC), address(mockController), owner
        );

        uint256 balanceAfter = IERC20(AAVE_TOKEN).balanceOf(owner);
        uint256 earnedRewards = balanceAfter - balanceBefore;

        assertEq(earnedRewards, 50e18, "AAVE Rewards transfer failed");
    }
}
