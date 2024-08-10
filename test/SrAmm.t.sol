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

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract SrAmmHookV2Test is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    SrAmmHookV2 hook;
    PoolId poolId;

    address attacker;
    address user;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();
        Deployers.deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.AFTER_SWAP_FLAG |
                    Hooks.AFTER_INITIALIZE_FLAG |
                    Hooks.AFTER_ADD_LIQUIDITY_FLAG |
                    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            ) ^ (0x4441 << 144) // Namespace the hook to avoid collisions
        );

        deployCodeTo("SrAmmHookV2.sol:SrAmmHookV2", abi.encode(manager), flags);
        hook = SrAmmHookV2(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        // Provide full-range liquidity to the pool
        // modifyLiquidityRouter.modifyLiquidity(
        //     key,
        //     IPoolManager.ModifyLiquidityParams(
        //         TickMath.minUsableTick(60),
        //         TickMath.maxUsableTick(60),
        //         10_000 ether, // 10000000000000000000000
        //         0
        //     ),
        //     ZERO_BYTES
        // );
        addLiquidityViaHook();
        fundAttackerUsers();
    }

    function addLiquidityViaHook() internal {
        MockERC20(Currency.unwrap(currency0)).approve(
            address(hook),
            10000 ether
        );
        MockERC20(Currency.unwrap(currency1)).approve(
            address(hook),
            10000 ether
        );

        hook.addLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(
                TickMath.minUsableTick(60),
                TickMath.maxUsableTick(60),
                10_000 ether, // 10000000000000000000000
                0
            ),
            ZERO_BYTES
        );
    }

    function fundAttackerUsers() internal {
        attacker = makeAddr("attacker");
        user = makeAddr("user");

        vm.deal(attacker, 1 ether);
        vm.deal(user, 1 ether);
    }

    function fundCurrencyAndApproveRouter(
        address to,
        Currency currency,
        uint256 amount
    ) internal {
        // TODO mint directly to user
        MockERC20(Currency.unwrap(currency)).transfer(to, amount);

        vm.startPrank(to);

        MockERC20(Currency.unwrap(currency)).approve(
            address(swapRouter),
            amount
        );

        vm.stopPrank();
    }

    function testSrPoolInitialized() public {
        (Slot0 bid, Slot0 offer) = hook.getSrPoolSlot0(key);

        assertEq(bid.sqrtPriceX96(), SQRT_PRICE_1_1);
        assertEq(offer.sqrtPriceX96(), SQRT_PRICE_1_1);
    }

    function testSwap1TokenOnSrPool() public {
        // positions were created in setup()

        // Perform a test swap //

        uint256 userAmount = 1 ether;
        fundCurrencyAndApproveRouter(user, currency1, userAmount);

        vm.startPrank(user);

        bool zeroForOne = false;

        // negative number indicates exact input swap!
        int256 amountSpecified = -1e18;

        BalanceDelta swapDelta = swap(
            key,
            zeroForOne,
            amountSpecified,
            ZERO_BYTES
        );
        vm.stopPrank();
        // ------------------- //

        assertEq(int256(swapDelta.amount1()), amountSpecified);

        uint256 userBalance0 = MockERC20(Currency.unwrap(currency0)).balanceOf(
            address(user)
        );

        assertGt(userBalance0, 0.99e17);
    }

    function testSrSwapOnSr001Pool() public {
        // positions were created in setup()

        (Slot0 bid, Slot0 offer) = hook.getSrPoolSlot0(key);
        console.log("Before Swap SQRT in Test.sol");
        console.log(bid.sqrtPriceX96());
        console.log(offer.sqrtPriceX96());

        // transfer token1 to attacker and user
        uint256 token1AttackerBeforeAmount = 10 ether;
        uint256 token1UserBeforeAmount = 100 ether;
        fundCurrencyAndApproveRouter(
            attacker,
            currency1,
            token1AttackerBeforeAmount
        );
        fundCurrencyAndApproveRouter(user, currency1, token1UserBeforeAmount);

        // Perform a test sandwich attack //
        {
            // ----attacker--- //
            console.log("attacker.......");
            vm.startPrank(attacker);

            // approval already given to swapRouter

            int256 attackerBuy1Amount = -int256(token1AttackerBeforeAmount); // negative number indicates exact input swap!
            BalanceDelta swapDelta = swap(
                key,
                false, //zerForOne false (buying at offerPrice, left to right)
                attackerBuy1Amount,
                ZERO_BYTES
            );
            vm.stopPrank();

            // ----user--- //
            console.log("User.......");
            vm.startPrank(user);
            // approval already given to swapRouter

            int256 userBuyAmount = -int256(token1UserBeforeAmount); // negative number indicates exact input swap!
            BalanceDelta swapDelta2 = swap(
                key,
                false, //zerForOne false (buying at offerPrice, left to right)
                userBuyAmount,
                ZERO_BYTES
            );
            vm.stopPrank();

            // --- attacker --- //
            vm.startPrank(attacker);
            console.log("Attacker........");

            // approve router to spend
            MockERC20(Currency.unwrap(currency0)).approve(
                address(swapRouter),
                10 ether
            );

            // negative number indicates exact input swap!
            int256 attackerSellAmount = -int256(
                MockERC20(Currency.unwrap(currency0)).balanceOf(
                    address(attacker)
                )
            );

            BalanceDelta swapDelta3 = swap(
                key,
                true, //zerForOne true (selling at bidPrice, right to left)
                attackerSellAmount,
                ZERO_BYTES
            );
            vm.stopPrank();
        }
        // ------------------- //

        console.log("After Swap SQRT in Test.sol");
        (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);
        console.log(bid2.sqrtPriceX96());
        console.log(offer2.sqrtPriceX96());

        console.log("Balance of token1 of after attack");
        uint256 attackerBalance = MockERC20(Currency.unwrap(currency1))
            .balanceOf(address(attacker));

        console.log(attackerBalance);
        console.log(
            MockERC20(Currency.unwrap(currency1)).balanceOf(address(user))
        );
        console.log("Diff");
        uint256 diff = token1AttackerBeforeAmount - attackerBalance;
        assertGt(token1AttackerBeforeAmount, attackerBalance);
        console.log(diff);
    }

    // buy 1 buy 1 sell 0
    function testSrSwapOnSr110Pool() public {
        // positions were created in setup()

        (Slot0 bid, Slot0 offer) = hook.getSrPoolSlot0(key);
        console.log("Before Swap SQRT in Test.sol");
        console.log(bid.sqrtPriceX96());
        console.log(offer.sqrtPriceX96());

        // trasfer token1 to attacker and user

        uint256 token0AttackerBeforeAmount = 10 ether;
        fundCurrencyAndApproveRouter(
            attacker,
            currency0,
            token0AttackerBeforeAmount
        );

        uint256 token0UserBeforeAmount = 100 ether;
        fundCurrencyAndApproveRouter(user, currency0, token0UserBeforeAmount);

        // Perform a test sandwich attack //
        {
            // ----attacker--- //
            console.log("attacker.......");
            vm.startPrank(attacker);

            //hookdata = abi.encode(attacker);
            int256 attackerBuy0Amount = -int256(token0AttackerBeforeAmount); // negative number indicates exact input swap!
            BalanceDelta swapDelta = swap(
                key,
                true, //zerForOne true (selling at bidPrice, right to left)
                attackerBuy0Amount,
                ZERO_BYTES
            );
            vm.stopPrank();

            // ----user--- //
            console.log("User.......");
            vm.startPrank(user);

            int256 userBuyAmount = -int256(token0UserBeforeAmount); // negative number indicates exact input swap!
            BalanceDelta swapDelta2 = swap(
                key,
                true, //zerForOne true (selling at bidPrice, right to left)
                userBuyAmount,
                ZERO_BYTES
            );
            vm.stopPrank();

            // --- attacker --- //
            vm.startPrank(attacker);
            console.log("Attacker........");

            // approve router to spend, as it needs to settle
            MockERC20(Currency.unwrap(currency1)).approve(
                address(swapRouter),
                10 ether
            );

            // negative number indicates exact input swap!
            int256 attackerSellAmount = -int256(
                MockERC20(Currency.unwrap(currency1)).balanceOf(
                    address(attacker)
                )
            );

            BalanceDelta swapDelta3 = swap(
                key,
                false, //zerForOne false (buying at offerPrice, left to right)
                attackerSellAmount,
                ZERO_BYTES
            );
            vm.stopPrank();
        }
        // ------------------- //

        console.log("After Swap SQRT in Test.sol");
        (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);
        console.log(bid2.sqrtPriceX96());
        console.log(offer2.sqrtPriceX96());

        uint256 attackerBalance = MockERC20(Currency.unwrap(currency0))
            .balanceOf(address(attacker));

        assertGt(token0AttackerBeforeAmount, attackerBalance);
        console.log("Diff");
        uint256 diff = token0AttackerBeforeAmount - attackerBalance;
        console.log(diff);
    }

    // 139014082579086214

    // Check if liquidity is handled correctly for OneForZero

    // Check the behaviour is correct in case of zeroForOne

    // Check if liquidity is handled correctly for zeroForOne

    // Check if liquidity is handled correctly for zeroForOne
}

// Normal Swap in PM: X1 -> Y1
// Custom Swap: X1 -> Y1Less

// Hooks settle Y1Less => PM
// PM settles penging        X1 -> (Y1 - Y1Less)

// Liquidity Scenario
