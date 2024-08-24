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
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";

import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {CurrencyDelta} from "v4-core/src/libraries/CurrencyDelta.sol";
import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";
import {SrAmm} from "./SrAmm.sol";

// test libs
import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";
import "forge-std/console.sol";

contract SrAmmHook is BaseHook, SrAmm {
    using PoolIdLibrary for PoolKey;
    // using StateLibrary for IPoolManager;
    using CurrencyDelta for Currency;
    using CurrencySettler for Currency;
    using CurrencySettler for Currency;
    // using BeforeSwapDeltaLibrary for int256;
    using TransientStateLibrary for IPoolManager;
    using SafeCast for uint256;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.ModifyLiquidityParams params;
        bytes hookData;
        bool settleUsingBurn;
        bool takeClaims;
    }

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
                afterAddLiquidity: false, // maintain artificial liquidity
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true, // custom swap accounting
                afterSwap: false, // settle reduced diffs
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true, // custom swap // not used atm
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
        BalanceDelta delta = srAmmSwap(key, params);
        console.log("SrAmmHook.sol: swap delta ");
        console.logInt(delta.amount0());
        console.logInt(delta.amount1());

        bool exactInput = params.amountSpecified < 0;
        (Currency specified, Currency unspecified) = (params.zeroForOne ==
            exactInput)
            ? (key.currency0, key.currency1)
            : (key.currency1, key.currency0);

        uint256 specifiedAmount = exactInput
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);

        int128 unspecifiedAmount;

        if (params.zeroForOne) {
            unspecifiedAmount = exactInput ? delta.amount1() : -delta.amount0();
        } else {
            unspecifiedAmount = exactInput ? delta.amount0() : -delta.amount1();
        }

        BeforeSwapDelta returnDelta;

        if (exactInput) {
            // in exact-input swaps, the specified token is a debt that gets paid down by the swapper
            // the unspecified token is credited to the PoolManager, that is claimed by the swapper
            specified.take(poolManager, address(this), specifiedAmount, true);
            unspecified.settle(
                poolManager,
                address(this),
                uint128(unspecifiedAmount),
                true
            );

            returnDelta = toBeforeSwapDelta(
                specifiedAmount.toInt128(),
                -unspecifiedAmount
            );
        } else {
            // exactOutput
            // in exact-output swaps, the unspecified token is a debt that gets paid down by the swapper
            // the specified token is credited to the PoolManager, that is claimed by the swapper

            unspecified.take(
                poolManager,
                address(this),
                uint128(unspecifiedAmount),
                true
            );
            specified.settle(poolManager, address(this), specifiedAmount, true);

            returnDelta = toBeforeSwapDelta(
                -specifiedAmount.toInt128(),
                unspecifiedAmount
            );
        }

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
        // revert here
        revert();

        return BaseHook.beforeAddLiquidity.selector;
    }

    // function initializePool(PoolKey memory key, uint160 sqrtPriceX96) external {
    //     // PoolKey memory key, uint160 sqrtPriceX96, bytes calldata hookData
    //     _initializePool(key, sqrtPriceX96);
    // }

    function afterSwap(
        address sender,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4, int128) {
        // console.log("After Swap delta");
        // console.logInt(delta.amount0());
        // console.logInt(delta.amount1());
        // console.logInt(unspecifiedDelta);

        //int128 diffSettledDelta = delta.amount0() + unspecifiedDelta;

        //console.logInt(diffSettledDelta);
        return (BaseHook.afterSwap.selector, 0);
    }

    // only testing
    function getSrPoolSlot0(
        PoolKey memory key
    ) public view returns (Slot0 bid, Slot0 offer) {
        SrPool.SrPoolState storage srPoolState = _srPools[key.toId()];

        return (srPoolState.bid, srPoolState.offer);
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

    // only testing
    function getSrPoolLiquidity(
        PoolKey memory key
    ) public view returns (uint128, uint128, uint128, uint128) {
        SrPool.SrPoolState storage srPoolState = _srPools[key.toId()];

        return (
            srPoolState.bidLiquidity,
            srPoolState.liquidity,
            srPoolState.virtualBidliquidity,
            srPoolState.virtualOfferliquidity
        );
    }

    // Add liquidity through the hook
    // Not for prod
    function addLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes memory hookData
    ) public payable returns (BalanceDelta delta) {
        // handle user liquidity mapping

        delta = abi.decode(
            poolManager.unlock(
                abi.encode(
                    CallbackData(msg.sender, key, params, hookData, false, true)
                )
            ),
            (BalanceDelta)
        );

        // uint256 ethBalance = address(this).balance;
        // if (ethBalance > 0) {
        //     CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        // }
    }

    /// @dev Handle liquidity addition by taking tokens from the sender and claiming ERC6909 to the hook address
    function unlockCallback(
        bytes calldata rawData
    ) external override poolManagerOnly returns (bytes memory) {
        CallbackData memory data = abi.decode(rawData, (CallbackData));

        // (BalanceDelta delta, ) = poolManager.modifyLiquidity(
        //     data.key,
        //     data.params,
        //     data.hookData
        // );
        int256 delta0 = -data.params.liquidityDelta;
        int256 delta1 = -data.params.liquidityDelta;
        //console.log("custom liqudity modifyLiquidity");
        // console.logInt(liquidityDelta);
        // console.logInt(delta.amount0());
        // console.logInt(delta.amount1());
        // (, , int256 delta0) = _fetchBalances(
        //     data.key.currency0,
        //     data.sender,
        //     address(this)
        // );
        // (, , int256 delta1) = _fetchBalances(
        //     data.key.currency1,
        //     data.sender,
        //     address(this)
        // );

        console.log("custom liqudity");
        console.logInt(delta0);
        console.logInt(delta1);

        data.key.currency0.settle(
            poolManager,
            data.sender,
            uint256(-delta0),
            data.settleUsingBurn
        );

        data.key.currency1.settle(
            poolManager,
            data.sender,
            uint256(-delta1),
            data.settleUsingBurn
        );

        data.key.currency0.take(
            poolManager,
            address(this),
            uint256(-delta0),
            data.takeClaims
        );

        data.key.currency1.take(
            poolManager,
            address(this),
            uint256(-delta1),
            data.takeClaims
        );

        srAmmAddLiquidity(data.key, data.params);
        console.log("custom liqudity added");
        return abi.encode(delta0, delta1);
    }

    function _fetchBalances(
        Currency currency,
        address user,
        address deltaHolder
    )
        internal
        view
        returns (uint256 userBalance, uint256 poolBalance, int256 delta)
    {
        userBalance = currency.balanceOf(user);
        poolBalance = currency.balanceOf(address(poolManager));
        delta = poolManager.currencyDelta(deltaHolder, currency);
    }
}
