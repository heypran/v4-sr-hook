// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {Slot0} from "v4-core/src/types/Slot0.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {SrAmmHookV2} from "../src/SrAmmHookV2.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {LiquidityMath} from "v4-core/src/libraries/LiquidityMath.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";
import {SrAmmUtils} from "./SrAmmUtils.t.sol";

contract SrAmmHookV2Test is SrAmmUtils {
    //ZEROFORONE CASES
    // 1. Testing liquidity changes for simple attack swap from zeroForOne. This invloves active liquidity remains unchanged
    function testSrSwapOnSrPoolActiveLiquidityRangeNoChangesZF1() public {
        addLiquidityViaHook(1000 ether, -3000, 3000);
        addLiquidityViaHook(1000 ether, -6000, -3000);
        console.log("Liquidity Before Attack");
        SandwichAttackSwap(true);
        console.log("After Swap SQRT Prices and ticks");
        (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);
        (
            uint128 bidLiquidity,
            uint128 liquidity,
            uint128 virtualBidLiquidity,
            uint128 virtualOfferliquidity
        ) = hook.getSrPoolLiquidity(key);
        assertGt(bid2.tick(), -3000);
        assertLt(offer2.tick(), 3000);
        assertEq(bidLiquidity, 1000 ether);
        assertEq(liquidity, 1000 ether);
        assertGt(virtualOfferliquidity, 0);
    }

    //2. Testing liquidity changes for simple attack swap from zero for one. This invloves active liquidity changes
    function testSrSwapOnSrPoolActiveLiquidityRangeChangesZF1() public {
        // positions were created in setup()
        (
            uint128 bidLiq,
            uint128 offerLiq,
            uint128 vBLiq,
            uint128 vOLiq,
            Slot0 intialBid,
            Slot0 initialOffer
        ) = displayPoolLiq(key);
        addLiquidityViaHook(1000 ether, -1800, 1800);
        addLiquidityViaHook(2000 ether, -6000, -1800);
        AttackerSwapTransaction(10 ether, true, false, attacker);
        console.log("Attacker zeroForOne");
        (
            uint128 bidLiq1,
            uint128 offerLiq1,
            uint128 vBLiq1,
            uint128 vOLiq1,
            Slot0 bid1,
            Slot0 offer1
        ) = displayPoolLiq(key);
        assertGt(intialBid.tick(), bid1.tick());
        assertEq(initialOffer.tick(), offer1.tick());
        assertGt(vOLiq1, 0);
        assertEq(vBLiq1, 0);
        assertEq(bidLiq1, offerLiq1); // The ticks is still in active range of -1800 to 1800
        UserSwapTransaction(100 ether, true, false, user);
        (
            uint128 bidLiq2,
            uint128 offerLiq2,
            uint128 vBLiq2,
            uint128 vOLiq2,
            Slot0 bid2,
            Slot0 offer2
        ) = displayPoolLiq(key);
        assertGt(bid1.tick(), bid2.tick());
        assertEq(initialOffer.tick(), offer2.tick());
        assertGt(vOLiq2, vOLiq1);
        assertEq(vBLiq2, 0);
        assertEq(bidLiq2, 2000 ether); // The ticks has move to another active range -6000, -1800
        MockERC20(Currency.unwrap(currency0)).approve(
            address(swapRouter),
            10 ether
        );
        uint256 attackerSellAmount = MockERC20(Currency.unwrap(currency1))
            .balanceOf(address(attacker));
        vm.startPrank(attacker);
        MockERC20(Currency.unwrap(currency1)).approve(
            address(swapRouter),
            10 ether
        );
        AttackerSwapTransaction(attackerSellAmount, false, true, attacker);
        vm.stopPrank();
        (
            uint128 bidLiq3,
            uint128 offerLiq3,
            uint128 vBLiq3,
            uint128 vOLiq3,
            Slot0 bid3,
            Slot0 offer3
        ) = displayPoolLiq(key);
        assertGt(offer3.tick(), offer2.tick());
        assertGt(vOLiq3, vOLiq2); // Is this should be less as we are moving on offer side ?
        assertEq(bidLiq3, 2000 ether);
    }

    // // 3. Testing in Overlapped liquidities
    // To check whether the active liqudity range amount changes based on the tick movement when it moves out of some liquidity ranges.
    function testSrSwapOnSrPoolMultipleOverlappedLiquidityZF1() public {
        // positions were created in setup()
        addLiquidityViaHook(10000 ether, -3000, 3000);
        addLiquidityViaHook(1000 ether, -60, 60);
        addLiquidityViaHook(1000 ether, 2000, 6000);
        addLiquidityViaHook(1000 ether, -24000, -12000);
        addLiquidityViaHook(1000 ether, -120, 120);
        displayPoolLiq(key);
        (
            uint128 bidLiquidityBefore,
            uint128 liquidityBefore,
            uint128 virtualBidLiquidityBefore,
            uint128 virtualOfferliquidityBefore
        ) = hook.getSrPoolLiquidity(key);
        assertEq(bidLiquidityBefore, 12000 ether);
        assertEq(liquidityBefore, 12000 ether);
        SandwichAttackSwap(true);
        console.log("After Swap SQRT Prices and ticks");
        (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);
        (
            uint128 bidLiquidity,
            uint128 liquidity,
            uint128 virtualBidLiquidity,
            uint128 virtualOfferliquidity
        ) = hook.getSrPoolLiquidity(key);
        displayPoolLiq(key);
        assertEq(bidLiquidity, 10000 ether);
        assertEq(liquidity, 12000 ether);
        assertGt(virtualOfferliquidity, 0);
    }

    //ONEFORZERO CASES
    // 1. Testing liquidity changes for simple attack swap from zero for one. This invloves no active change in liquidity
    function testSrSwapOnSrPoolActiveLiquidityRangeNoChanges1FZ() public {
        addLiquidityViaHook(1000 ether, -3000, 3000);
        addLiquidityViaHook(1000 ether, 3000, 6000);
        SandwichAttackSwap(false);
        (Slot0 bid, Slot0 offer) = hook.getSrPoolSlot0(key);
        (
            uint128 bidLiquidity,
            uint128 liquidity,
            uint128 virtualBidLiquidity,
            uint128 virtualOfferliquidity
        ) = hook.getSrPoolLiquidity(key);
        assertLt(bid.tick(), 0);
        assertGt(offer.tick(), 0);
        assertEq(bidLiquidity, 1000 ether);
        assertEq(liquidity, 1000 ether);
        assertGt(virtualBidLiquidity, 0 ether);
        assertEq(virtualOfferliquidity, 0 ether);
    }

    // 2. Testing liquidity changes for simple attack swap from zero for one. This invloves active liquidity changes
    function testSrSwapOnSrPoolActiveLiquidityRangeChanges1FZ() public {
        // positions were created in setup()
        addLiquidityViaHook(1000 ether, -1800, 1800);
        addLiquidityViaHook(1000 ether, 1800, 6000);
        displayPoolLiq(key);
        SandwichAttackOneToZeroSwap();
        (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);
        (
            uint128 bidLiquidity,
            uint128 liquidity,
            uint128 virtualBidLiquidity,
            uint128 virtualOfferliquidity
        ) = hook.getSrPoolLiquidity(key);
        assertEq(bidLiquidity, 1000 ether);
        assertEq(liquidity, 1000 ether);
        assertGt(virtualBidLiquidity, 0);
        assertEq(virtualOfferliquidity, 0 ether);
    }

    //3. Testing in Overlapped liquidities
    // To check whether the active liqudity range amount changes based on the tick movement when it moves out of some liquidity ranges.
    function testSrSwapOnSrPoolMultipleOverlappedLiquidity1FZ() public {
        // positions were created in setup()
        addLiquidityViaHook(10000 ether, -3000, 3000);
        addLiquidityViaHook(1000 ether, -60, 60);
        addLiquidityViaHook(1000 ether, -6000, -2000);
        addLiquidityViaHook(1000 ether, 12000, 24000);
        addLiquidityViaHook(1000 ether, -120, 120);
        (
            uint128 bidLiquidityBefore,
            uint128 liquidityBefore,
            uint128 virtualBidLiquidityBefore,
            uint128 virtualOfferliquidityBefore
        ) = hook.getSrPoolLiquidity(key);
        assertEq(bidLiquidityBefore, 12000 ether);
        assertEq(liquidityBefore, 12000 ether);
        SandwichAttackOneToZeroSwap();
        console.log("After Swap SQRT Prices and ticks");
        (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);
        (
            uint128 bidLiquidity,
            uint128 liquidity,
            uint128 virtualBidLiquidity,
            uint128 virtualOfferliquidity
        ) = hook.getSrPoolLiquidity(key);
        assertEq(bidLiquidity, 12000 ether);
        assertEq(liquidity, 10000 ether);
        assertGt(virtualBidLiquidity, 0);
        assertEq(virtualOfferliquidity, 0);
    }
}
