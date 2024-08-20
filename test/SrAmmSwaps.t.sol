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
    function testMultipleSwapAttackTransaction_WithinCurrentBlock() public {
        addLiquidityViaHook(
            1000 ether,
            TickMath.minUsableTick(1),
            TickMath.maxUsableTick(1)
        );

        AttackerSwapTransaction(10 ether, true, false, attacker);
        UserSwapTransaction(100 ether, true, false, user);

        uint256 attackerAmountCurrency0 = AttackerSellBackTheCurrency(
            10 ether,
            attacker,
            true
        );

        assertLt(attackerAmountCurrency0, 10 ether);
        uint256 userAmountCurrency0 = UserSellBackTheCurrency(
            100 ether,
            user,
            true
        );
        assertLt(attackerAmountCurrency0, 10 ether);
        assertLt(userAmountCurrency0, 100 ether);

        console.log("First Attack");
        console.logUint(attackerAmountCurrency0);
        console.logUint(userAmountCurrency0);
        console.log("Second Attack");
        SandwichAttackSwap(true);
        uint256 userFinalAmountCurrency0 = UserSellBackTheCurrency(
            100 ether,
            user,
            true
        );
        uint256 attackerFinalAmountCurrency0 = MockERC20(
            Currency.unwrap(currency0)
        ).balanceOf(address(attacker));
        assertLt(attackerFinalAmountCurrency0, 20 ether); // 19.4 ether
        assertLt(userFinalAmountCurrency0, 200 ether); // 159.8 ether
    }

    function testSwapAttackTransaction_InDifferentBlock() public {
        addLiquidityViaHook(
            10000 ether,
            TickMath.minUsableTick(1),
            TickMath.maxUsableTick(1)
        );

        AttackerSwapTransaction(10 ether, true, false, attacker);
        UserSwapTransaction(100 ether, true, false, user);
        uint256 attackerAmountCurrency0 = AttackerSellBackTheCurrency(
            10 ether,
            attacker,
            true
        );
        assertLt(attackerAmountCurrency0, 10 ether);
        vm.roll(block.number + 1);
        displayPoolLiq(key);
        AttackerSwapTransaction(10 ether, true, false, attacker);
        UserSwapTransaction(100 ether, true, false, user);
        vm.startPrank(attacker);
        uint256 attackerSellAmount = MockERC20(Currency.unwrap(currency1))
            .balanceOf(address(attacker));
        MockERC20(Currency.unwrap(currency1)).approve(
            address(swapRouter),
            attackerSellAmount
        );
        AttackerSwapTransaction(attackerSellAmount, false, true, attacker);
        uint256 attackerFinalBalance = MockERC20(Currency.unwrap(currency0))
            .balanceOf(address(attacker));
        vm.stopPrank();

        vm.startPrank(user);
        console.log("user........");

        displayPoolLiq(key);

        // approve router to spend, as it needs to settle
        MockERC20(Currency.unwrap(currency1)).approve(
            address(swapRouter),
            200 ether
        );

        // negative number indicates exact input swap!
        int256 userSellAmount = -int256(
            MockERC20(Currency.unwrap(currency1)).balanceOf(address(user))
        );
        console.log("user........userSellAmount");

        BalanceDelta swapDelta3 = swap(
            key,
            false, //zerForOne false (buying at offerPrice, left to right)
            userSellAmount,
            ZERO_BYTES
        );
        vm.stopPrank();
        assertLt(attackerFinalBalance, 20 ether); //19.95 ether
    }

    function testSwapAttackTransaction_WithDifferentLiquidity() public {
        addLiquidityViaHook(1000 ether, -1000, 1000);
        addLiquidityViaHook(500 ether, -100, 100);
        addLiquidityViaHook(1000 ether, -2000, 3000);
        addLiquidityViaHook(10000 ether, -12000, 12000);
        displayPoolLiq(key);

        AttackerSwapTransaction(10 ether, true, false, attacker);
        UserSwapTransaction(100 ether, true, false, user);
        uint256 attackerSellAmount = MockERC20(Currency.unwrap(currency1))
            .balanceOf(address(attacker));

        vm.startPrank(attacker);
        MockERC20(Currency.unwrap(currency1)).approve(
            address(swapRouter),
            10 ether
        );
        AttackerSwapTransaction(attackerSellAmount, false, true, attacker);
        vm.stopPrank();
        displayPoolLiq(key);
        uint256 attackerFinalAmount = MockERC20(Currency.unwrap(currency0))
            .balanceOf(address(attacker));
        console.logUint(attackerFinalAmount);

        assertLt(attackerFinalAmount, 10 ether);

        uint256 userSellAmount = MockERC20(Currency.unwrap(currency1))
            .balanceOf(address(user));

        vm.startPrank(user);
        MockERC20(Currency.unwrap(currency1)).approve(
            address(swapRouter),
            100 ether
        );
        UserSwapTransaction(userSellAmount, false, true, user);
        vm.stopPrank();
        uint256 userFinalAmount = MockERC20(Currency.unwrap(currency0))
            .balanceOf(address(user));

        assertLt(userFinalAmount, 100 ether);
    }
}
