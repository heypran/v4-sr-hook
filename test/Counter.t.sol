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
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Counter} from "../src/Counter.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract CounterTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    address attacker;
    address user;
    Counter hook;
    PoolId poolId;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();
        Deployers.deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.AFTER_SWAP_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        deployCodeTo("Counter.sol:Counter", abi.encode(manager), flags);
        hook = Counter(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 1, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        // Provide full-range liquidity to the pool
        fundAttackerUsers();
    }

    function testMultipleSwapsFullRange() public {
        addLiquidity(
            1000 ether,
            TickMath.minUsableTick(1),
            TickMath.maxUsableTick(1)
        );

        AttackerSwapTransaction(10 ether, true, false);
        UserSwapTransaction(100 ether, true, false);
        UserSellBackTheCurrency(100 ether);
        AttackerSellBackTheCurrency(10 ether);
        UserSwapTransaction(100 ether, true, false);
        AttackerSwapTransaction(10 ether, true, false);
        uint256 attackerFinalAmount = AttackerSellBackTheCurrency(10 ether);
        uint256 userFinalAmount = UserSellBackTheCurrency(100 ether);

        console.log("After multiple swaps----->");
        console.logUint(attackerFinalAmount);
        console.logUint(userFinalAmount);
    }

    function testSwapAttackTransactionInFullRange() public {
        addLiquidity(
            1000 ether,
            TickMath.minUsableTick(1),
            TickMath.maxUsableTick(1)
        );

        AttackerSwapTransaction(10 ether, true, false);
        UserSwapTransaction(100 ether, true, false);
        uint256 attackerSellAmount = MockERC20(Currency.unwrap(currency1))
            .balanceOf(address(attacker));

        vm.startPrank(attacker);
        MockERC20(Currency.unwrap(currency1)).approve(
            address(swapRouter),
            10 ether
        );
        AttackerSwapTransaction(attackerSellAmount, false, true);
        vm.stopPrank();

        uint256 attackerFinalAmount = MockERC20(Currency.unwrap(currency0))
            .balanceOf(address(attacker));
        console.logUint(attackerFinalAmount);

        assertGt(attackerFinalAmount, 10 ether);

        uint256 userSellAmount = MockERC20(Currency.unwrap(currency1))
            .balanceOf(address(user));

        vm.startPrank(user);
        MockERC20(Currency.unwrap(currency1)).approve(
            address(swapRouter),
            100 ether
        );
        UserSwapTransaction(userSellAmount, false, true);
        vm.stopPrank();
        uint256 userFinalAmount = MockERC20(Currency.unwrap(currency0))
            .balanceOf(address(user));
        console.logUint(userFinalAmount);

        assertLt(userFinalAmount, 100 ether);
    }

    function testMultipleSwapAttackTransactionInFullRange() public {
        addLiquidity(
            1000 ether,
            TickMath.minUsableTick(1),
            TickMath.maxUsableTick(1)
        );

        AttackerSwapTransaction(10 ether, true, false);
        UserSwapTransaction(100 ether, true, false);
        uint256 attackerSellAmount = MockERC20(Currency.unwrap(currency1))
            .balanceOf(address(attacker));

        vm.startPrank(attacker);
        MockERC20(Currency.unwrap(currency1)).approve(
            address(swapRouter),
            10 ether
        );
        AttackerSwapTransaction(attackerSellAmount, false, true);
        vm.stopPrank();

        uint256 attackerFinalAmount = MockERC20(Currency.unwrap(currency0))
            .balanceOf(address(attacker));
        console.logUint(attackerFinalAmount);

        assertGt(attackerFinalAmount, 10 ether);

        uint256 userSellAmount = MockERC20(Currency.unwrap(currency1))
            .balanceOf(address(user));

        vm.startPrank(user);
        MockERC20(Currency.unwrap(currency1)).approve(
            address(swapRouter),
            100 ether
        );
        UserSwapTransaction(userSellAmount, false, true);
        vm.stopPrank();
        uint256 userFinalAmount = MockERC20(Currency.unwrap(currency0))
            .balanceOf(address(user));
        console.logUint(userFinalAmount);

        assertLt(userFinalAmount, 100 ether);

        SandwichAttackZeroToOneSwap();
        uint256 attackerFinalAmount1 = MockERC20(Currency.unwrap(currency0))
            .balanceOf(address(attacker));
        uint256 userSellAmount1 = MockERC20(Currency.unwrap(currency1))
            .balanceOf(address(user));

        console.log("test---test0000====");

        console.logUint(attackerFinalAmount1);
        console.logUint(userSellAmount1);
    }

    //ZEROFORONE CASES
    // 1. Testing liquidity changes for simple attack swap from zero for one. This invloves active liquidity remains unchanged
    function testSrSwapOnSrPoolActiveLiquidityRangeNoChangesZF1() public {
        // positions were created in setup()
        addLiquidity(1000 ether, -3000, 3000);

        addLiquidity(2000 ether, -6000, -3000);
        // Before attack active range liquidity is -1000 to 3000
        console.log("Liquidity Before Attack");
        uint128 liquidityBefore = StateLibrary.getLiquidity(manager, poolId);
        console.logUint(liquidityBefore);
        assertEq(liquidityBefore, 1000 ether);

        SandwichAttackZeroToOneSwap();

        console.log("After Swap SQRT Prices and ticks");
        (uint160 sqrtPriceX96, int24 tick, , uint24 lpFee) = StateLibrary
            .getSlot0(manager, poolId);
        console.log("Slot0 Info----");
        console.logUint(sqrtPriceX96);
        console.logInt(tick);

        uint128 liquidityAfter = StateLibrary.getLiquidity(manager, poolId);
        console.log("Liquidity After");
        console.logUint(liquidityAfter);
        // In this case the tick still remains in the active range and not crossed the to different active range
        assertEq(liquidityAfter, 1000 ether);
    }

    // //2. Testing liquidity changes for simple attack swap from zero for one. This invloves active liquidity changes
    function testSrSwapOnSrPoolActiveLiquidityRangeChangesZF1() public {
        // positions were created in setup()

        addLiquidity(1000 ether, -1000, 3000);

        addLiquidity(2000 ether, -6000, -1000);

        // Before attack active range liquidity is -1000 to 2000
        console.log("Liquidity Before Attack");
        uint128 liquidityBefore = StateLibrary.getLiquidity(manager, poolId);
        console.logUint(liquidityBefore);
        assertEq(liquidityBefore, 1000 ether);

        SandwichAttackZeroToOneSwap();

        console.log("After Swap SQRT Prices and ticks");
        (uint160 sqrtPriceX96, int24 tick, , uint24 lpFee) = StateLibrary
            .getSlot0(manager, poolId);
        console.log("Slot0 Info----");
        console.logUint(sqrtPriceX96);
        console.logInt(tick);

        uint128 liquidityAfter = StateLibrary.getLiquidity(manager, poolId);
        console.log("Liquidity After");
        console.logUint(liquidityAfter);
        // In this case the tick moves to next active range between -6000 to -1000 and uses that liquidity of the range
        assertEq(liquidityAfter, 2000 ether);
    }

    // 3. Testing in Overlapped liquidities
    // To check whether the active liqudity range amount changes based on the tick movement when it moves out of some liquidity ranges.

    function testSrSwapOnSrPoolMultipleOverlappedLiquidityZF1() public {
        // positions were created in setup()

        addLiquidity(10000 ether, -3000, 3000);
        addLiquidity(1000 ether, -60, 60);

        addLiquidity(1000 ether, 2000, 6000);

        addLiquidity(1000 ether, -24000, -12000);

        addLiquidity(1000 ether, -120, 120);

        // Before attack active range liquidity is -1000 to 2000
        console.log("Liquidity Before Attack");
        uint128 liquidityBefore = StateLibrary.getLiquidity(manager, poolId);
        console.logUint(liquidityBefore);
        assertEq(liquidityBefore, 12000 ether);

        SandwichAttackZeroToOneSwap();

        console.log("After Swap SQRT Prices and ticks");
        (uint160 sqrtPriceX96, int24 tick, , uint24 lpFee) = StateLibrary
            .getSlot0(manager, poolId);
        console.log("Slot0 Info----");
        console.logUint(sqrtPriceX96);
        console.logInt(tick);

        uint128 liquidityAfter = StateLibrary.getLiquidity(manager, poolId);
        console.log("Liquidity After");
        console.logUint(liquidityAfter);
        assertEq(liquidityAfter, 10000 ether);
    }

    //    //ONEFORZERO CASES
    //    // 1. Testing liquidity changes for simple attack swap from zero for one. This invloves active liquidity remains unchanged
    function testSrSwapOnSrPoolActiveLiquidityRangeNoChanges1FZ() public {
        addLiquidity(1000 ether, -3000, 3000);
        addLiquidity(1000 ether, 3000, 6000);

        console.log("Liquidity Before Attack");
        uint128 liquidityBefore = StateLibrary.getLiquidity(manager, poolId);
        console.logUint(liquidityBefore);
        assertEq(liquidityBefore, 1000 ether);

        SandwichAttackOneToZeroSwap();

        console.log("After Swap SQRT Prices and ticks");
        (uint160 sqrtPriceX96, int24 tick, , uint24 lpFee) = StateLibrary
            .getSlot0(manager, poolId);
        console.log("Slot0 Info----");
        console.logUint(sqrtPriceX96);
        console.logInt(tick);
        console.logInt(tick);

        uint128 liquidity = StateLibrary.getLiquidity(manager, poolId);
        console.log("Liquidity After");
        console.logUint(liquidity);
        assertEq(liquidity, 1000 ether);
    }

    // 2. Testing liquidity changes for simple attack swap from zero for one. This invloves active liquidity changes
    function testSrSwapOnSrPoolActiveLiquidityRangeChanges1FZ() public {
        // positions were created in setup()

        addLiquidity(1000 ether, -1800, 1800);
        addLiquidity(2000 ether, 1800, 6000);

        console.log("Liquidity Before Attack");
        uint128 liquidityBefore = StateLibrary.getLiquidity(manager, poolId);
        console.logUint(liquidityBefore);
        assertEq(liquidityBefore, 1000 ether);

        SandwichAttackOneToZeroSwap();

        console.log("After Swap SQRT Prices and ticks");
        (uint160 sqrtPriceX96, int24 tick, , uint24 lpFee) = StateLibrary
            .getSlot0(manager, poolId);
        console.log("Slot0 Info----");
        console.logUint(sqrtPriceX96);
        console.logInt(tick);

        uint128 liquidity = StateLibrary.getLiquidity(manager, poolId);
        console.log("Liquidity After");
        console.logUint(liquidity);
        assertEq(liquidity, 2000 ether);
    }

    // 3. Testing in Overlapped liquidities
    // To check whether the active liqudity range amount changes based on the tick movement when it moves out of some liquidity ranges.

    function testSrSwapOnSrPoolMultipleOverlappedLiquidity1FZ() public {
        // positions were created in setup()

        addLiquidity(10000 ether, -3000, 3000);
        addLiquidity(1000 ether, -60, 60);

        addLiquidity(1000 ether, -6000, -2000);

        addLiquidity(1000 ether, 3000, 24000);

        addLiquidity(1000 ether, 12000, 24000);

        addLiquidity(1000 ether, -120, 120);

        addLiquidity(4000 ether, -120, 1000);

        // Before attack active range liquidity is -1000 to 2000
        console.log("Liquidity Before Attack");
        uint128 liquidityBefore = StateLibrary.getLiquidity(manager, poolId);
        console.logUint(liquidityBefore);
        assertEq(liquidityBefore, 16000 ether);

        SandwichAttackOneToZeroSwap();

        console.log("After Swap SQRT Prices and ticks");
        (uint160 sqrtPriceX96, int24 tick, , uint24 lpFee) = StateLibrary
            .getSlot0(manager, poolId);
        console.log("Slot0 Info----");
        console.logUint(sqrtPriceX96);
        console.logInt(tick);
        console.logInt(tick);

        uint128 liquidityAfter = StateLibrary.getLiquidity(manager, poolId);
        console.log("Liquidity After");
        console.logUint(liquidityAfter);
        assertEq(liquidityAfter, 14000 ether);
    }

    function addLiquidity(
        int256 liquidityDelta,
        int24 minTick,
        int24 maxTick
    ) internal {
        MockERC20(Currency.unwrap(currency0)).approve(
            address(hook),
            10000 ether
        );
        MockERC20(Currency.unwrap(currency1)).approve(
            address(hook),
            10000 ether
        );

        hook.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(
                minTick,
                maxTick,
                liquidityDelta,
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

    function AttackerSwapTransaction(
        uint256 amount,
        bool isZeroForOne,
        bool hasBalance
    ) public {
        if (isZeroForOne) {
            if (!hasBalance)
                fundCurrencyAndApproveRouter(attacker, currency0, amount);
            vm.startPrank(attacker);
            BalanceDelta swapDelta = swap(
                key,
                true, //zerForOne true (selling at bidPrice, right to left)
                -int256(amount), // negative number indicates exact input swap!
                ZERO_BYTES
            );
            vm.stopPrank();
        } else {
            if (!hasBalance) {
                fundCurrencyAndApproveRouter(attacker, currency1, amount);
            }
            vm.startPrank(attacker);
            console.logInt(-int256(amount));
            BalanceDelta swapDelta = swap(
                key,
                false, //oneForZero true (selling at offerPrice, left to right)
                -int256(amount), // negative number indicates exact input swap!
                ZERO_BYTES
            );
            vm.stopPrank();
        }
    }

    function UserSwapTransaction(
        uint256 amount,
        bool isZeroForOne,
        bool hasBalance
    ) public {
        if (isZeroForOne) {
            if (!hasBalance) {
                fundCurrencyAndApproveRouter(user, currency0, amount);
            }
            vm.startPrank(user);
            BalanceDelta swapDelta = swap(
                key,
                true, //zerForOne true (selling at bidPrice, right to left)
                -int256(amount), // negative number indicates exact input swap!
                ZERO_BYTES
            );
            vm.stopPrank();
        } else {
            if (!hasBalance) {
                fundCurrencyAndApproveRouter(user, currency1, amount);
            }
            vm.startPrank(user);
            BalanceDelta swapDelta = swap(
                key,
                false, //oneForZero true (selling at offerPrice, left to right)
                -int256(amount), // negative number indicates exact input swap!
                ZERO_BYTES
            );
            vm.stopPrank();
        }
    }

    function SandwichAttackZeroToOneSwap() public {
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
    }

    function AttackerSellBackTheCurrency(
        uint256 swapRouterAmount
    ) public returns (uint256 balance) {
        vm.startPrank(attacker);
        uint256 attackerSellAmount = MockERC20(Currency.unwrap(currency1))
            .balanceOf(address(attacker));
        MockERC20(Currency.unwrap(currency1)).approve(
            address(swapRouter),
            swapRouterAmount
        );
        AttackerSwapTransaction(attackerSellAmount, false, true);
        vm.stopPrank();
        uint256 attackerFinalBalance = MockERC20(Currency.unwrap(currency0))
            .balanceOf(address(attacker));
        return attackerFinalBalance;
    }

    function UserSellBackTheCurrency(
        uint256 swapRouterAmount
    ) public returns (uint256 balance) {
        vm.startPrank(user);
        uint256 userSellAmount = MockERC20(Currency.unwrap(currency1))
            .balanceOf(address(user));
        MockERC20(Currency.unwrap(currency1)).approve(
            address(swapRouter),
            swapRouterAmount
        );
        UserSwapTransaction(userSellAmount, false, true);
        vm.stopPrank();
        uint256 userFinalBalance = MockERC20(Currency.unwrap(currency0))
            .balanceOf(address(user));
        return userFinalBalance;
    }

    function SandwichAttackOneToZeroSwap() public {
        // trasfer token10 to attacker and user

        uint256 token1AttackerBeforeAmount = 10 ether;
        fundCurrencyAndApproveRouter(
            attacker,
            currency1,
            token1AttackerBeforeAmount
        );

        uint256 token1UserBeforeAmount = 100 ether;
        fundCurrencyAndApproveRouter(user, currency1, token1UserBeforeAmount);

        // Perform a test sandwich attack //
        {
            // ----attacker--- //
            console.log("attacker.......");
            vm.startPrank(attacker);

            //hookdata = abi.encode(attacker);
            int256 attackerBuy1Amount = -int256(token1AttackerBeforeAmount); // negative number indicates exact input swap!
            BalanceDelta swapDelta = swap(
                key,
                false, //oneForZero true (selling at offerPrice, left to right)
                attackerBuy1Amount,
                ZERO_BYTES
            );
            vm.stopPrank();

            // ----user--- //
            console.log("User.......");
            vm.startPrank(user);

            int256 userBuyAmount = -int256(token1UserBeforeAmount); // negative number indicates exact input swap!
            BalanceDelta swapDelta2 = swap(
                key,
                false, //oneForZero true (selling at offerPrice, left to right)
                userBuyAmount,
                ZERO_BYTES
            );
            vm.stopPrank();

            // --- attacker --- //
            vm.startPrank(attacker);
            console.log("Attacker........");

            // approve router to spend, as it needs to settle
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
                true, //zerForOne true (buying at bidPrice, right to left)
                attackerSellAmount,
                ZERO_BYTES
            );
            vm.stopPrank();
        }
        // ------------------- //
    }
}
