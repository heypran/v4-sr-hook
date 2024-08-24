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
import {SrAmmHook} from "../src/SrAmmHook.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {LiquidityMath} from "v4-core/src/libraries/LiquidityMath.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";
import {ISrAmm} from "../src/ISrAmm.sol";
import {SrAmmUtils} from "./SrAmmUtils.t.sol";

// test events
contract SrAmmIntializedEvent is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    SrAmmHook hook;
    PoolId poolId;

    int24 tickSpacing = 1;

    function testHookInitializeEmitEvent() public {
        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();
        Deployers.deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.AFTER_INITIALIZE_FLAG |
                    Hooks.BEFORE_SWAP_FLAG |
                    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            ) ^ (0x4411 << 144) // Namespace the hook to avoid collisions
        );

        deployCodeTo("SrAmmHook.sol:SrAmmHook", abi.encode(manager), flags);
        hook = SrAmmHook(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 100, tickSpacing, IHooks(hook));
        poolId = key.toId();
        // TODO: check bid and offer tick is initialized
        vm.expectEmit(true, true, true, true, address(manager));
        emit IPoolManager.Initialize(
            key.toId(),
            key.currency0,
            key.currency1,
            key.fee,
            key.tickSpacing,
            key.hooks
        );
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);
    }
}

contract SrAmmHookSwapEventsTest is SrAmmUtils {
    function testSwapEmitEventZF1() public {
        addLiquidityViaHook(
            10000 ether,
            TickMath.minUsableTick(1),
            TickMath.maxUsableTick(1)
        );
        fundCurrencyAndApproveRouter(user, currency0, 10 ether);
        vm.startPrank(user);
        vm.expectEmit(true, true, true, false);
        emit ISrAmm.Swapped(
            poolId,
            address(swapRouter),
            -10000000000000000000,
            9989011986914284407,
            79228162514264337593543950336,
            10000000000000000000000,
            0,
            100
        );
        BalanceDelta swapDelta = swap(key, true, -int256(10 ether), ZERO_BYTES);
        vm.stopPrank();
    }

    function testSwapEmitEvent1FZ() public {
        addLiquidityViaHook(
            10000 ether,
            TickMath.minUsableTick(1),
            TickMath.maxUsableTick(1)
        );
        fundCurrencyAndApproveRouter(user, currency1, 10 ether);
        vm.startPrank(user);
        vm.expectEmit(true, true, true, false);
        emit ISrAmm.Swapped(
            poolId,
            address(swapRouter),
            9989011986914284407,
            -10000000000000000000,
            79307382753962350504703734931,
            10000000000000000000000,
            19,
            100
        );

        BalanceDelta swapDelta = swap(
            key,
            false,
            -int256(10 ether),
            ZERO_BYTES
        );
        vm.stopPrank();
    }
}
