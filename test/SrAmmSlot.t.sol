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
import {ISrAmmv2} from "../src/ISrAmmV2.sol";
import {SrAmmUtils} from "./SrAmmUtils.t.sol";

// Slot (consider slot as block number, 12 sec for Ethereum)
contract SrAmmHookSlotTest is SrAmmUtils {
    function testMultipleSwapsFullRangeZF1() public {
        addLiquidityViaHook(
            10000 ether,
            TickMath.minUsableTick(1),
            TickMath.maxUsableTick(1)
        );

        userSwapTransaction(10 ether, true, false, user);
        (, , , , Slot0 bid1, Slot0 offer1) = displayPoolLiq(key);
        assertEq(offer1.tick(), 0);
        assertEq(bid1.tick(), -20);

        userSwapTransaction(100 ether, true, false, user2);
        (, , , , Slot0 bid2, Slot0 offer2) = displayPoolLiq(key);

        assertEq(offer2.tick(), 0);
        assertEq(bid2.tick(), -219);
        assertEq(block.number, 1);

        vm.roll(block.number + 1);

        assertEq(block.number, 2);

        (, , , , Slot0 bid3, Slot0 offer3) = displayPoolLiq(key);

        userSwapTransaction(20 ether, true, false, user3);
        assertLt(bid3.tick(), 0);
        // assertGt(bid3.tick(), bid2.tick());
        uint256 userFinalAmount = userSellBackTheCurrency(10 ether, user, true);
        uint256 user2FinalAmount = userSellBackTheCurrency(
            100 ether,
            user2,
            true
        );
        userSwapTransaction(100 ether, true, false, user3);
        displayPoolLiq(key);
        vm.roll(block.number + 1);
        assertEq(block.number, 3);
        displayPoolLiq(key);
        uint256 user3FinalAmount = userSellBackTheCurrency(
            120 ether,
            user3,
            true
        );

        console.logUint(userFinalAmount);
        console.logUint(user2FinalAmount);
        console.logUint(user3FinalAmount);
    }

    function testMultipleSwapsFullRange1FZ() public {
        addLiquidityViaHook(
            10000 ether,
            TickMath.minUsableTick(1),
            TickMath.maxUsableTick(1)
        );
        userSwapTransaction(10 ether, false, false, user);
        (, , , , Slot0 bid1, Slot0 offer1) = displayPoolLiq(key);
        assertEq(offer1.tick(), 19);
        assertEq(bid1.tick(), 0);

        userSwapTransaction(100 ether, false, false, user2);
        (, , , , Slot0 bid2, Slot0 offer2) = displayPoolLiq(key);
        assertEq(offer2.tick(), 218);
        assertEq(bid2.tick(), 0);
        assertEq(block.number, 1);
        vm.roll(block.number + 1);
        assertEq(block.number, 2);
        uint256 userFinalAmount = userSellBackTheCurrency(
            10 ether,
            user,
            false
        );
        (, , , , Slot0 bid3, Slot0 offer3) = displayPoolLiq(key);
        assertGt(bid3.tick(), 0); // After the block incremented and during the next swap the ticks get reset to the offer tick.
        displayPoolLiq(key);
        uint256 user2FinalAmount = userSellBackTheCurrency(
            100 ether,
            user2,
            false
        );
        userSwapTransaction(100 ether, false, false, user3);
        displayPoolLiq(key);
        vm.roll(block.number + 1);
        assertEq(block.number, 3);
        displayPoolLiq(key);
        uint256 user3FinalAmount = userSellBackTheCurrency(
            100 ether,
            user3,
            false
        );
    }
}
