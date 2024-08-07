// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

import {SrPool} from "./SrPool.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {LiquidityMath} from "v4-core/src/libraries/LiquidityMath.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {SwapMath} from "v4-core/src/libraries/SwapMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {FixedPoint128} from "v4-core/src/libraries/FixedPoint128.sol";

import {ProtocolFeeLibrary} from "v4-core/src/libraries/ProtocolFeeLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Slot0} from "v4-core/src/types/Slot0.sol";
import {BalanceDelta, toBalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {CurrencyDelta} from "v4-core/src/libraries/CurrencyDelta.sol";
import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";
import {SrAmmV2} from "./SrAmmV2.sol";

import "forge-std/console.sol";

contract SrAmmHookV2 is BaseHook, SrAmmV2 {
    using PoolIdLibrary for PoolKey;
    // using StateLibrary for IPoolManager;
    using CurrencyDelta for Currency;
    using CurrencySettler for Currency;
    // using BeforeSwapDeltaLibrary for int256;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    struct SlotPrice {
        int24 tick;
        uint160 SqrtX96Price;
    }

    struct HookPoolState {
        SlotPrice bid;
        SlotPrice offer;
    }

    mapping(PoolId => uint256 count) public beforeSwapCount;
    mapping(PoolId => uint256 count) public afterSwapCount;

    mapping(PoolId => uint256 count) public beforeAddLiquidityCount;
    mapping(PoolId => uint256 count) public beforeRemoveLiquidityCount;

    HookPoolState public hookPoolState;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true, // initialize srPool
                beforeAddLiquidity: true, // revert
                afterAddLiquidity: true, // maintain artificial liquidity
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true, // custom swap
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true, // custom swap
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------
    uint256 lastBlockNumber;
    mapping(uint256 => int24) slotOfferTickMap;
    mapping(uint256 => uint160) slotOfferSqrtMap;

    function checkSlotChanged() public returns (bool) {
        if (block.number != lastBlockNumber) {
            // lastBlockNumber = block.number;
            return true;
        } else {
            return false;
        }
    }

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        beforeSwapCount[key.toId()]++;

        BalanceDelta delta = srAmmSwap(key, params);
        console.log("SrAmmHook.sol: swap delta ");
        console.logInt(delta.amount0());
        console.logInt(delta.amount1());

        address swapper = abi.decode(hookData, (address));

        settleOutputTokenPostSwap(key, params, delta, swapper);

        // Handling only one case for now
        // oneForZero and exactInput
        // poolManager.sync(key.currency0);
        // poolManager.sync(key.currency1);
        BeforeSwapDelta returnDelta = toBeforeSwapDelta(0, delta.amount0());

        return (BaseHook.beforeSwap.selector, returnDelta, 0);
    }

    function settleOutputTokenPostSwap(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        address sender
    ) internal {
        // data.testSettings.settleUsingBurn - false
        console.log("Settling tokens");
        console.logInt(delta.amount0());
        console.logInt(delta.amount1());

        // if (delta.amount0() < 0) {
        //     poolManager.sync(key.currency0);

        //     IERC20Minimal(Currency.unwrap(key.currency0)).transferFrom(
        //         address(sender),
        //         address(poolManager),
        //         uint128(-delta.amount0())
        //     );
        //     poolManager.settle(key.currency0);
        // }

        // if (delta.amount1() < 0) {
        //     console.log("Settling amount1");
        //     poolManager.sync(key.currency1);

        //     IERC20Minimal(Currency.unwrap(key.currency1)).transferFrom(
        //         address(sender),
        //         address(poolManager),
        //         uint128(-delta.amount1())
        //     );

        //     poolManager.settle(key.currency1);
        // }
        // poolManager.sync(key.currency1);
        // poolManager.sync(key.currency0);
        if (delta.amount0() > 0) {
            console.log("taking amount0");
            poolManager.take(key.currency0, sender, uint128(delta.amount0()));
        }
        if (delta.amount1() > 0) {
            console.log("taking amount1");
            poolManager.take(key.currency1, sender, uint128(delta.amount1()));
        }

        console.log("Settled!");
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        beforeAddLiquidityCount[key.toId()]++;

        // revert here
        // not used currently
        return BaseHook.beforeAddLiquidity.selector;
    }

    function afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick,
        bytes calldata hookData
    ) external override returns (bytes4) {
        // PoolKey memory key, uint160 sqrtPriceX96, bytes calldata hookData
        _initializePool(key, sqrtPriceX96);
        // Implement your logic here
        return BaseHook.afterInitialize.selector;
    }

    function initializePool(PoolKey memory key, uint160 sqrtPriceX96) external {
        // PoolKey memory key, uint160 sqrtPriceX96, bytes calldata hookData
        _initializePool(key, sqrtPriceX96);
    }

    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4, BalanceDelta) {
        srAmmAddLiquidity(key, params);

        return (
            BaseHook.afterAddLiquidity.selector,
            BalanceDeltaLibrary.ZERO_DELTA
        );
    }

    function getSrPoolSlot0(
        PoolKey memory key
    ) public view returns (Slot0 bid, Slot0 offer) {
        SrPool.SrPoolState storage srPoolState = _srPools[key.toId()];

        return (srPoolState.bid, srPoolState.offer);
    }
}
