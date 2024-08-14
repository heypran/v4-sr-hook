// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import "forge-std/Test.sol";
// import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
// import {Hooks} from "v4-core/src/libraries/Hooks.sol";
// import {TickMath} from "v4-core/src/libraries/TickMath.sol";
// import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
// import {PoolKey} from "v4-core/src/types/PoolKey.sol";
// import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
// import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
// import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
// import {Slot0} from "v4-core/src/types/Slot0.sol";
// import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
// import {Deployers} from "v4-core/test/utils/Deployers.sol";
// import {Counter} from "../src/Counter.sol";
// import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
// import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

// contract OldAmmSwap is Test, Deployers {
//     using PoolIdLibrary for PoolKey;
//     using CurrencyLibrary for Currency;
//     using StateLibrary for IPoolManager;

//     Counter hook;
//     PoolId poolId;
//     PoolKey key;

//     address attacker;
//     address user;

//     int24 tickSpacing = 1;

//     function setUp() public {
//         // creates the pool manager, utility routers, and test tokens
//         Deployers.deployFreshManagerAndRouters();
//         Deployers.deployMintAndApprove2Currencies();

//         // Deploy the hook to an address with the correct flags
//         address flags = address(
//             uint160(
//                     Hooks.BEFORE_SWAP_FLAG |
//                     Hooks.AFTER_SWAP_FLAG |
//                     Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
//                     Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
//             ) ^ (0x4441 << 144) // Namespace the hook to avoid collisions
//         );

//         deployCodeTo("Counter.sol:Counter", abi.encode(manager), flags);
//         hook = Counter(flags);

//         // Create the pool
//         key = PoolKey(currency0, currency1, 100, tickSpacing, IHooks(hook));
//         poolId = key.toId();
//         manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

//         addLiquidityViaHook(
//             10_000 ether,
//             TickMath.minUsableTick(tickSpacing),
//             TickMath.maxUsableTick(tickSpacing)
//         );
//         fundAttackerUsers();
//     }

//     function addLiquidityViaHook(
//         int256 liquidityDelta,
//         int24 minTick,
//         int24 maxTick
//     ) internal {
//         MockERC20(Currency.unwrap(currency0)).approve(
//             address(hook),
//             10000 ether
//         );
//         MockERC20(Currency.unwrap(currency1)).approve(
//             address(hook),
//             10000 ether
//         );

//         hook.modifyLiquidity(
//             key,
//             IPoolManager.ModifyLiquidityParams(
//                 minTick,
//                 maxTick,
//                 liquidityDelta,
//                 0
//             ),
//             ZERO_BYTES
//         );
//     }

//     function fundAttackerUsers() internal {
//         attacker = makeAddr("attacker");
//         user = makeAddr("user");

//         vm.deal(attacker, 1 ether);
//         vm.deal(user, 1 ether);
//     }

//     function fundCurrencyAndApproveRouter(
//         address to,
//         Currency currency,
//         uint256 amount
//     ) internal {
//         // TODO mint directly to user
//         MockERC20(Currency.unwrap(currency)).transfer(to, amount);

//         vm.startPrank(to);

//         MockERC20(Currency.unwrap(currency)).approve(
//             address(swapRouter),
//             amount
//         );

//         vm.stopPrank();
//     }

//     // Function to get reserves (balances) of the pool for a given currency
//     function getReserve(Currency currency) internal view returns (uint256) {
//         address tokenAddress = Currency.unwrap(currency);
//         return MockERC20(tokenAddress).balanceOf(address(hook));
//     }

//     function testBasicSwap() public {
//         uint256 initialReserve0 = getReserve(currency0);
//         uint256 initialReserve1 = getReserve(currency1);

//         uint256 amountIn = 100 ether;
//         uint256 amountOut = hook.swap(currency0, currency1, amountIn);

//         uint256 finalReserve0 = getReserve(currency0);
//         uint256 finalReserve1 = getReserve(currency1);

//         assertEq(finalReserve0, initialReserve0 + amountIn);
//         assertEq(finalReserve1, initialReserve1 - amountOut);
//     }

//     function testBoundarySwap() public {
//         uint256 maxInput = hook.getMaxInput(currency0);

//         uint256 initialReserve0 = getReserve(currency0);
//         uint256 initialReserve1 = getReserve(currency1);

//         uint256 amountOut = hook.swap(currency0, currency1, maxInput);

//         uint256 finalReserve0 = getReserve(currency0);
//         uint256 finalReserve1 = getReserve(currency1);

//         assertEq(finalReserve0, initialReserve0 + maxInput);
//         assertEq(finalReserve1, initialReserve1 - amountOut);
//     }

//     function testMultipleSwaps() public {
//         uint256 amountIn = 100 ether;

//         for (uint i = 0; i < 10; i++) {
//             hook.swap(currency0, currency1, amountIn);
//         }

//         uint256 finalReserve0 = getReserve(currency0);
//         uint256 finalReserve1 = getReserve(currency1);

//         assertTrue(finalReserve0 > 10000 ether);
//         assertTrue(finalReserve1 < 10000 ether);
//     }

//     function testHighSlippageSwap() public {
//         uint256 amountIn = 900 ether;
//         uint256 expectedOut = hook.getExpectedOutput(currency0, currency1, amountIn);

//         uint256 amountOut = hook.swap(currency0, currency1, amountIn);

//         uint256 slippage = expectedOut - amountOut;

//         assertTrue(slippage <= expectedOut * 0.05); // Assuming 5% slippage tolerance
//     }

//     function testImbalancedSwap() public {
//         addLiquidityViaHook(1000 ether, TickMath.minUsableTick(tickSpacing), TickMath.maxUsableTick(tickSpacing));

//         uint256 amountIn = 10 ether;
//         uint256 amountOut = hook.swap(currency0, currency1, amountIn);

//         uint256 finalReserve0 = getReserve(currency0);
//         uint256 finalReserve1 = getReserve(currency1);

//         assertTrue(finalReserve0 > 1000 ether);
//         assertTrue(finalReserve1 < 100 ether);
//     }
// }
