// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LederoHelper} from "../helpers/LederoHelper.t.sol";
import {MigrationParams} from "../../src/interfaces/internal/ILederoTypes.sol";
import {MockAaveRewardsController} from "../mock/MockAaveRewardsController.sol";
import {MockCompoundRewardsController} from "../mock/MockCompoundRewardsController.sol";
import {IAaveV3Pool} from "../../src/interfaces/external/IAaveV3Pool.sol";
import {IComet} from "../../src/interfaces/external/ICompound.sol";

contract LederoForkTest is LederoHelper {
    function test_OpenAndUnwindPosition_Aave() public {
        _helperOpenPositionAave(0.1e8);

        uint256 debtBeforeUnwind = _helperGetDebtAAVE(address(ledero));
        assertTrue(debtBeforeUnwind > 0, "Debt should exist before unwind");

        _helperUnwindPositionAave();

        uint256 debtAfterUnwind = _helperGetDebtAAVE(address(ledero));

        assertTrue(debtAfterUnwind == 0, "Debt should be 0 after unwind");
    }

    function test_OpenAndUnwindPosition_Compound() public {
        _helperOpenPositionCompound(0.1e8);

        uint256 debtBeforeUnwind = _helperGetDebtCompound(address(ledero));
        assertTrue(debtBeforeUnwind > 0, "Compound: Debt should exist before unwind");

        _helperUnwindPositionCompound();

        uint256 debtAfterUnwind = _helperGetDebtCompound(address(ledero));

        assertTrue(debtAfterUnwind < debtBeforeUnwind, "Compound: Debt should be reduced after unwind");
    }

    function test_claimProtocolRewards_AaveV3_Success() public {
        address AAVE_TOKEN = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;

        MockAaveRewardsController mockController = new MockAaveRewardsController(AAVE_TOKEN);

        deal(AAVE_TOKEN, address(mockController), 1000 * 10 ** 18);

        uint256 balanceBefore = IERC20(AAVE_TOKEN).balanceOf(owner);

        vm.prank(owner);
        ledero.claimProtocolRewards(
            address(aaveAdapter), AAVE_POOL, address(USDC), address(WBTC), address(mockController), owner
        );

        uint256 balanceAfter = IERC20(AAVE_TOKEN).balanceOf(owner);
        uint256 earnedRewards = balanceAfter - balanceBefore;

        assertEq(earnedRewards, 50e18, "AAVE Rewards transfer failed");
    }

    function test_claimProtocolRewards_CompoundV3_Success() public {
        address dummyCometPool = address(0x3333);

        address COMP_TOKEN = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

        MockCompoundRewardsController mockController = new MockCompoundRewardsController(COMP_TOKEN);

        deal(COMP_TOKEN, address(mockController), 1000 * 10 ** 18);

        uint256 balanceBefore = IERC20(COMP_TOKEN).balanceOf(owner);

        vm.prank(owner);

        ledero.claimProtocolRewards(
            address(compoundAdapter), dummyCometPool, address(USDC), address(WBTC), address(mockController), owner
        );

        uint256 balanceAfter = IERC20(COMP_TOKEN).balanceOf(owner);
        uint256 earnedRewards = balanceAfter - balanceBefore;

        assertEq(earnedRewards, 30e18, "Compound Rewards transfer failed");
    }

    function test_Migrate_Aave_To_CompoundV3() public {
        uint256 collateralAmount = 0.1e8; // 0.1 WBTC

        _helperOpenPositionAave(collateralAmount);

        IAaveV3Pool.ReserveData memory usdcData = IAaveV3Pool(AAVE_POOL).getReserveData(address(USDC));
        IAaveV3Pool.ReserveData memory wbtcData = IAaveV3Pool(AAVE_POOL).getReserveData(address(WBTC));

        uint256 fullColToMigrate = IERC20(wbtcData.aTokenAddress).balanceOf(address(ledero));
        uint256 fullDebtToMigrate = IERC20(usdcData.variableDebtTokenAddress).balanceOf(address(ledero));

        assertTrue(fullDebtToMigrate > 0, "Aave position not opened");

        MigrationParams memory migParams = MigrationParams({
            collateralToken: address(WBTC),
            collateralAmount: fullColToMigrate,
            debtToken: address(USDC),
            debtAmount: fullDebtToMigrate,
            fromPool: AAVE_POOL,
            minCollateralToSupply: (fullColToMigrate * 99) / 100,
            toPool: COMPOUND_USDC_COMET,
            lendingAdapterFrom: address(aaveAdapter),
            lendingAdapterTo: address(compoundAdapter),
            flashAdapter: address(balancerAdapter),
            deadline: block.timestamp + 1 hours
        });

        vm.prank(owner);
        ledero.migratePosition(migParams);

        uint256 aaveDebtAfter = _helperGetDebtAAVE(address(ledero));
        assertApproxEqAbs(aaveDebtAfter, 0, 10, "Aave debt should be cleared");

        uint256 compCollateral = IComet(COMPOUND_USDC_COMET).collateralBalanceOf(address(ledero), address(WBTC));
        assertTrue(compCollateral > collateralAmount, "Compound missing leveraged collateral");

        uint256 compDebt = _helperGetDebtCompound(address(ledero));
        assertApproxEqAbs(compDebt, fullDebtToMigrate, 10, "Migrated debt mismatch");
    }

    function test_Migrate_CompoundV3_To_Aave() public {
        uint256 collateralAmount = 0.1e8;

        _helperOpenPositionCompound(collateralAmount);

        uint256 fullColToMigrate = IComet(COMPOUND_USDC_COMET).collateralBalanceOf(address(ledero), address(WBTC));
        uint256 fullDebtToMigrate = _helperGetDebtCompound(address(ledero));

        assertTrue(fullDebtToMigrate > 0, "Compound position not opened");

        MigrationParams memory migParams = MigrationParams({
            collateralToken: address(WBTC),
            collateralAmount: fullColToMigrate,
            debtToken: address(USDC),
            debtAmount: fullDebtToMigrate,
            fromPool: COMPOUND_USDC_COMET,
            minCollateralToSupply: (fullColToMigrate * 99) / 100,
            toPool: AAVE_POOL,
            lendingAdapterFrom: address(compoundAdapter),
            lendingAdapterTo: address(aaveAdapter),
            flashAdapter: address(balancerAdapter),
            deadline: block.timestamp + 1 hours
        });

        vm.prank(owner);
        ledero.migratePosition(migParams);

        uint256 compDebtAfter = _helperGetDebtCompound(address(ledero));
        assertApproxEqAbs(compDebtAfter, 0, 10, "Compound debt should be cleared");

        uint256 compColAfter = IComet(COMPOUND_USDC_COMET).collateralBalanceOf(address(ledero), address(WBTC));
        assertEq(compColAfter, 0, "Compound collateral should be withdrawn");

        _verifyPositionAave(address(ledero));
    }
}
