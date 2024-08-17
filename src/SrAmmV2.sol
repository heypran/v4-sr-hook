// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
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
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";

import {CurrencyDelta} from "v4-core/src/libraries/CurrencyDelta.sol";
import {NoDelegateCall} from "v4-core/src/NoDelegateCall.sol";
import {Reserves} from "v4-core/src/libraries/Reserves.sol";

contract SrAmmV2 is NoDelegateCall {
    using PoolIdLibrary for PoolKey;
    using SrPool for *;
    using SafeCast for *;
    // using Position for mapping(bytes32 => Position.Info);
    using CurrencyDelta for Currency;
    using Reserves for Currency;

    using LPFeeLibrary for uint24;

    mapping(PoolId id => SrPool.SrPoolState) internal _srPools;
    mapping(PoolId id => uint256 lastBlock) internal _lastBlock;

    event Swap(
        PoolId indexed id,
        address sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    function _initializePool(
        PoolKey memory key,
        uint160 sqrtPriceX96
    ) internal noDelegateCall returns (int24 bidTick, int24 offerTick) {
        PoolId id = key.toId();
        uint24 lpFee = key.fee.getInitialLPFee();
        uint24 protocolFee = 0;
        (bidTick, offerTick) = _srPools[id].initialize(
            sqrtPriceX96,
            protocolFee,
            lpFee
        );
    }

    function srAmmSwap(
        PoolKey memory key,
        IPoolManager.SwapParams memory params
    ) internal returns (BalanceDelta swapDelta) {
        resetSlot(key);

        (
            BalanceDelta result,
            ,
            uint24 swapFee,
            SrPool.SrSwapState memory srSwapState
        ) = _srPools[key.toId()].swap(
                SrPool.SwapParams({
                    tickSpacing: key.tickSpacing,
                    zeroForOne: params.zeroForOne,
                    amountSpecified: params.amountSpecified,
                    sqrtPriceLimitX96: params.sqrtPriceLimitX96,
                    lpFeeOverride: 0
                })
            );

        emit Swap(
            key.toId(),
            msg.sender,
            result.amount0(),
            result.amount1(),
            srSwapState.sqrtPriceX96,
            srSwapState.liquidity,
            srSwapState.tick,
            swapFee
        );

        return result;
    }

    function srAmmAddLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params
    ) internal returns (BalanceDelta liquidityDelta) {
        (BalanceDelta result, ) = _srPools[key.toId()].modifyLiquidity(
            SrPool.ModifyLiquidityParams({
                owner: msg.sender,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: params.liquidityDelta.toInt128(),
                tickSpacing: key.tickSpacing,
                salt: params.salt
            })
        );

        return result;
    }

    function resetSlot(PoolKey memory key) internal returns (bool) {
        if (_lastBlock[key.toId()] == block.number) {
            return false;
        }

        _srPools[key.toId()].initializeAtNewSlot();
        _lastBlock[key.toId()] = block.number;

        return true;
    }
}
