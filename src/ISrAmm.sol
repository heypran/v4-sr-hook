// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {PoolId} from "v4-core/src/types/PoolId.sol";

interface ISrAmm {
    event Swapped(
        PoolId id,
        address sender,
        int128 indexed amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 indexed tick,
        uint24 indexed fee
    );
}
