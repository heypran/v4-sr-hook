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

contract SrAmmHookV2OldTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    SrAmmHookV2 hook;
    PoolId poolId;

    address attacker;
    address user;

    int24 tickSpacing = 1;

    function setUp() public {
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

        deployCodeTo("SrAmmHookV2.sol:SrAmmHookV2", abi.encode(manager), flags);
        hook = SrAmmHookV2(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 100, tickSpacing, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        // Not using this
        // Provide full-range liquidity to the pool
        // modifyLiquidityRouter.modifyLiquidity(
        //     key,
        //     IPoolManager.ModifyLiquidityParams(
        //         -2,
        //         2,
        //         10_000 ether, // 10000000000000000000000
        //         0
        //     ),
        //     ZERO_BYTES
        // );

        // addLiquidityViaHook(
        //     10_000 ether,
        //     TickMath.minUsableTick(tickSpacing),
        //     TickMath.maxUsableTick(tickSpacing)
        // );
        fundAttackerUsers();
    }

    // function testMultipleSwapsFullRange() public {
    //     addLiquidityViaHook(
    //         1000 ether,
    //         TickMath.minUsableTick(1),
    //         TickMath.maxUsableTick(1)
    //     );

    //     AttackerSwapTransaction(10 ether, true, false);
    //     UserSwapTransaction(100 ether, true, false);
    //     UserSellBackTheCurrency(100 ether);
    //     AttackerSellBackTheCurrency(10 ether);
    //     UserSwapTransaction(100 ether, true, false);
    //     AttackerSwapTransaction(10 ether, true, false);
    //     uint256 attackerFinalAmount = AttackerSellBackTheCurrency(10 ether);
    //     uint256 userFinalAmount = UserSellBackTheCurrency(100 ether);

    //     console.log("After multiple swaps----->");
    //     console.logUint(attackerFinalAmount);
    //     console.logUint(userFinalAmount);
    // }

    // function testSwapAttackTransactionInFullRange() public {
    //     addLiquidityViaHook(
    //         1000 ether,
    //         TickMath.minUsableTick(1),
    //         TickMath.maxUsableTick(1)
    //     );

    //     AttackerSwapTransaction(10 ether, true, false);
    //     UserSwapTransaction(100 ether, true, false);
    //     uint256 attackerSellAmount = MockERC20(Currency.unwrap(currency1))
    //         .balanceOf(address(attacker));

    //     vm.startPrank(attacker);
    //     MockERC20(Currency.unwrap(currency1)).approve(
    //         address(swapRouter),
    //         10 ether
    //     );
    //     AttackerSwapTransaction(attackerSellAmount, false, true);
    //     vm.stopPrank();

    //     uint256 attackerFinalAmount = MockERC20(Currency.unwrap(currency0))
    //         .balanceOf(address(attacker));
    //     console.logUint(attackerFinalAmount);

    //     assertLt(attackerFinalAmount, 10 ether);

    //     uint256 userSellAmount = MockERC20(Currency.unwrap(currency1))
    //         .balanceOf(address(user));

    //     vm.startPrank(user);
    //     MockERC20(Currency.unwrap(currency1)).approve(
    //         address(swapRouter),
    //         100 ether
    //     );
    //     UserSwapTransaction(userSellAmount, false, true);
    //     vm.stopPrank();
    //     uint256 userFinalAmount = MockERC20(Currency.unwrap(currency0))
    //         .balanceOf(address(user));
    //     console.logUint(userFinalAmount);

    //     assertLt(userFinalAmount, 100 ether);
    // }

    // function testMultipleSwapAttackTransactionInFullRange() public {
    //     addLiquidityViaHook(
    //         1000 ether,
    //         TickMath.minUsableTick(1),
    //         TickMath.maxUsableTick(1)
    //     );

    //     AttackerSwapTransaction(10 ether, true, false);
    //     UserSwapTransaction(100 ether, true, false);

    //     uint256 attackerAmountCurrency0 = AttackerSellBackTheCurrency(10 ether);

    //     assertLt(attackerAmountCurrency0, 10 ether);
    //     uint256 userAmountCurrency0 = UserSellBackTheCurrency(100 ether);
    //     assertLt(attackerAmountCurrency0, 10 ether);
    //     assertLt(userAmountCurrency0, 100 ether);

    //     console.log("First Attack");
    //     console.logUint(attackerAmountCurrency0);
    //     console.logUint(userAmountCurrency0);
    //     console.log("Second Attack");
    //     SandwichAttackZeroToOneSwap();
    //     uint256 userFinalAmountCurrency0 = UserSellBackTheCurrency(100 ether);
    //     uint256 attackerFinalAmountCurrency0 = MockERC20(
    //         Currency.unwrap(currency0)
    //     ).balanceOf(address(attacker));
    //     assertLt(attackerFinalAmountCurrency0, 20 ether); // 19.4 ether
    //     assertLt(userFinalAmountCurrency0, 200 ether); // 159.8 ether
    // }

    function testSwapAttackTransactionInFullRange() public {
        addLiquidityViaHook(
            10000 ether,
            TickMath.minUsableTick(1),
            TickMath.maxUsableTick(1)
        );

        AttackerSwapTransaction(10 ether, true, false);
        UserSwapTransaction(100 ether, true, false);
        uint256 attackerAmountCurrency0 = AttackerSellBackTheCurrency(10 ether);
        assertLt(attackerAmountCurrency0, 10 ether);
        vm.roll(block.number + 1);
        displayPoolLiq(key);
        AttackerSwapTransaction(10 ether, true, false);
        UserSwapTransaction(100 ether, true, false);
        vm.startPrank(attacker);
        uint256 attackerSellAmount = MockERC20(Currency.unwrap(currency1))
            .balanceOf(address(attacker));
        MockERC20(Currency.unwrap(currency1)).approve(
            address(swapRouter),
            attackerSellAmount
        );
        AttackerSwapTransaction(attackerSellAmount, false, true);
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

        //     uint256 userSellAmount = MockERC20(Currency.unwrap(currency1))
        //         .balanceOf(address(user));
        //     MockERC20(Currency.unwrap(currency1)).approve(
        //         address(swapRouter),
        //         10 ether
        //     );
        //               console.log("displayPoolLiq2---------------->");
        //     displayPoolLiq(key);
        //             vm.startPrank(user);
        //    BalanceDelta swapDelta = swap(
        //             key,
        //             false, //oneForZero true (selling at offerPrice, left to right)
        //             -int256(10 ether), // negative number indicates exact input swap!
        //             ZERO_BYTES
        //         );
        //     // uint256 userFinalBalance = MockERC20(Currency.unwrap(currency0))
        //     //     .balanceOf(address(user));
        //      vm.stopPrank();
        assertLt(attackerFinalBalance, 20 ether); //19.95 ether
        console.log("attackerSellAmount000", attackerFinalBalance);
    }

    // // //ZEROFORONE CASES
    // // // // 1. Testing liquidity changes for simple attack swap from zero for one. This invloves active liquidity remains unchanged
    // function testSrSwapOnSrPoolActiveLiquidityRangeNoChangesZF1() public {
    //     // positions were created in setup()

    //     addLiquidityViaHook(1000 ether, -3000, 3000);

    //     addLiquidityViaHook(1000 ether, -6000, -3000);

    //     console.log("Liquidity Before Attack");

    //     displayPoolLiq(key);

    //     SandwichAttackZeroToOneSwap();

    //     console.log("After Swap SQRT Prices and ticks");
    //     (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);

    //     (
    //         uint128 bidLiquidity,
    //         uint128 liquidity,
    //         uint128 virtualBidLiquidity,
    //         uint128 virtualOfferliquidity
    //     ) = hook.getSrPoolLiquidity(key);

    //     assertEq(bidLiquidity, 1000 ether);
    //     assertEq(liquidity, 1000 ether);
    //     // assertEq(virtualBidLiquidity, 0 ether);
    //     // assertEq(virtualOfferliquidity, 0 ether);
    // }

    //2. Testing liquidity changes for simple attack swap from zero for one. This invloves active liquidity changes
    // function testSrSwapOnSrPoolActiveLiquidityRangeChangesZF1() public {
    //     // positions were created in setup()
    //     (
    //         uint128 bidLiq,
    //         uint128 offerLiq,
    //         uint128 vBLiq,
    //         uint128 vOLiq,
    //         Slot0 intialBid,
    //         Slot0 initialOffer
    //     ) = displayPoolLiq(key);
    //     addLiquidityViaHook(1000 ether, -1800, 1800);

    //     addLiquidityViaHook(2000 ether, -6000, -1800);

    //     // displayPoolLiq(key);

    //     // SandwichAttackZeroToOneSwap();
    //     AttackerSwapTransaction(10 ether, true, false);
    //     console.log("Attacker zeroForOne");
    //     (
    //         uint128 bidLiq1,
    //         uint128 offerLiq1,
    //         uint128 vBLiq1,
    //         uint128 vOLiq1,
    //         Slot0 bid1,
    //         Slot0 offer1
    //     ) = displayPoolLiq(key);

    //     assertGt(intialBid.tick(), bid1.tick());
    //     assertEq(initialOffer.tick(), offer1.tick());
    //     assertGt(vOLiq1, 0);
    //     assertEq(vBLiq1, 0);
    //     assertEq(bidLiq1, offerLiq1); // The ticks is still in active range of -1800 to 1800

    //     UserSwapTransaction(100 ether, true, false);
    //     console.log("User zeroForOne");
    //     (
    //         uint128 bidLiq2,
    //         uint128 offerLiq2,
    //         uint128 vBLiq2,
    //         uint128 vOLiq2,
    //         Slot0 bid2,
    //         Slot0 offer2
    //     ) = displayPoolLiq(key);

    //     assertGt(bid1.tick(), bid2.tick());
    //     assertEq(initialOffer.tick(), offer2.tick());
    //     assertGt(vOLiq2, vOLiq1);
    //     assertEq(vBLiq2, 0);
    //     assertEq(bidLiq2, 2000 ether); // The ticks has move to another active range -6000, -1800

    //     MockERC20(Currency.unwrap(currency0)).approve(
    //         address(swapRouter),
    //         10 ether
    //     );
    //     console.log("FInal Attacker zeroForOne");

    //     uint256 attackerSellAmount = MockERC20(Currency.unwrap(currency1))
    //         .balanceOf(address(attacker));

    //     vm.startPrank(attacker);
    //     MockERC20(Currency.unwrap(currency1)).approve(
    //         address(swapRouter),
    //         10 ether
    //     );
    //     AttackerSwapTransaction(attackerSellAmount, false, true);
    //     vm.stopPrank();

    //     (
    //         uint128 bidLiq3,
    //         uint128 offerLiq3,
    //         uint128 vBLiq3,
    //         uint128 vOLiq3,
    //         Slot0 bid3,
    //         Slot0 offer3
    //     ) = displayPoolLiq(key);
    //     console.log("------> THE END 1 ------>");
    //     console.logUint(offerLiq3);
    //     assertEq(bid3.tick(), bid2.tick());
    //     assertGt(offer3.tick(), offer2.tick()); // offer2 or initialoffer were same but in the oneTozero swap bid remain same and offer ticks changes
    //     // assertEq(vBLiq3, 0);
    //     assertEq(vOLiq3, vOLiq2);
    //     assertEq(bidLiq3, 2000 ether);

    //     console.log("attackerSellAmount-----", attackerSellAmount);

    //     // calculateVirtualLiquidity(
    //     //     bid.sqrtPriceX96(),
    //     //     SQRT_PRICE_1_1,
    //     //     bidLiquidity,
    //     //     true
    //     // );
    // }

    // // 3. Testing in Overlapped liquidities
    // // To check whether the active liqudity range amount changes based on the tick movement when it moves out of some liquidity ranges.

    // function testSrSwapOnSrPoolMultipleOverlappedLiquidityZF1() public {
    //     // positions were created in setup()

    //     addLiquidityViaHook(10000 ether, -3000, 3000);
    //     addLiquidityViaHook(1000 ether, -60, 60);
    //     addLiquidityViaHook(1000 ether, 2000, 6000);
    //     addLiquidityViaHook(1000 ether, -24000, -12000);
    //     addLiquidityViaHook(1000 ether, -120, 120);

    //     displayPoolLiq(key);

    //     (
    //         uint128 bidLiquidityBefore,
    //         uint128 liquidityBefore,
    //         uint128 virtualBidLiquidityBefore,
    //         uint128 virtualOfferliquidityBefore
    //     ) = hook.getSrPoolLiquidity(key);

    //     assertEq(bidLiquidityBefore, 12000 ether);
    //     assertEq(liquidityBefore, 12000 ether);

    //     SandwichAttackZeroToOneSwap();

    //     console.log("After Swap SQRT Prices and ticks");
    //     (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);

    //     (
    //         uint128 bidLiquidity,
    //         uint128 liquidity,
    //         uint128 virtualBidLiquidity,
    //         uint128 virtualOfferliquidity
    //     ) = hook.getSrPoolLiquidity(key);

    //     assertEq(bidLiquidity, 10000 ether);
    //     assertEq(liquidity, 12000 ether);
    //     // assertEq(virtualOfferliquidity, 12000 ether); // 12000 or 2000 extra
    // }

    // // //ONEFORZERO CASES
    // // // 1. Testing liquidity changes for simple attack swap from zero for one. This invloves no active change in liquidity
    // function testSrSwapOnSrPoolActiveLiquidityRangeNoChanges1FZ() public {
    //     // positions were created in setup()

    //     addLiquidityViaHook(1000 ether, -3000, 3000);
    //     addLiquidityViaHook(1000 ether, 3000, 6000);

    //     displayPoolLiq(key);

    //     SandwichAttackOneToZeroSwap();

    //     console.log("After Swap SQRT Prices and ticks");
    //     (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);

    //     (
    //         uint128 bidLiquidity,
    //         uint128 liquidity,
    //         uint128 virtualBidLiquidity,
    //         uint128 virtualOfferliquidity
    //     ) = hook.getSrPoolLiquidity(key);

    //     assertEq(bidLiquidity, 1000 ether);
    //     assertEq(liquidity, 1000 ether);
    //     // assertEq(virtualBidLiquidity, 0 ether);
    //     // assertEq(virtualOfferliquidity, 0 ether);
    // }

    // // // 2. Testing liquidity changes for simple attack swap from zero for one. This invloves active liquidity changes
    // function testSrSwapOnSrPoolActiveLiquidityRangeChanges1FZ() public {
    //     // positions were created in setup()

    //     addLiquidityViaHook(1000 ether, -1800, 1800);
    //     addLiquidityViaHook(1000 ether, 1800, 6000);

    //     displayPoolLiq(key);

    //     SandwichAttackOneToZeroSwap();

    //     (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);

    //     (
    //         uint128 bidLiquidity,
    //         uint128 liquidity,
    //         uint128 virtualBidLiquidity,
    //         uint128 virtualOfferliquidity
    //     ) = hook.getSrPoolLiquidity(key);

    //     assertEq(bidLiquidity, 1000 ether);
    //     assertEq(liquidity, 1000 ether);
    //     // assertEq(virtualBidLiquidity, 1000 ether);
    //     // assertEq(virtualOfferliquidity, 0 ether);
    // }

    // // // 3. Testing in Overlapped liquidities
    // // // To check whether the active liqudity range amount changes based on the tick movement when it moves out of some liquidity ranges.

    // function testSrSwapOnSrPoolMultipleOverlappedLiquidity1FZ() public {
    //     // positions were created in setup()

    //     addLiquidityViaHook(10000 ether, -3000, 3000);
    //     addLiquidityViaHook(1000 ether, -60, 60);
    //     addLiquidityViaHook(1000 ether, -6000, -2000);
    //     addLiquidityViaHook(1000 ether, 12000, 24000);
    //     addLiquidityViaHook(1000 ether, -120, 120);

    //     displayPoolLiq(key);

    //     (
    //         uint128 bidLiquidityBefore,
    //         uint128 liquidityBefore,
    //         uint128 virtualBidLiquidityBefore,
    //         uint128 virtualOfferliquidityBefore
    //     ) = hook.getSrPoolLiquidity(key);

    //     assertEq(bidLiquidityBefore, 12000 ether);
    //     assertEq(liquidityBefore, 12000 ether);

    //     SandwichAttackOneToZeroSwap();

    //     console.log("After Swap SQRT Prices and ticks");
    //     (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);

    //     (
    //         uint128 bidLiquidity,
    //         uint128 liquidity,
    //         uint128 virtualBidLiquidity,
    //         uint128 virtualOfferliquidity
    //     ) = hook.getSrPoolLiquidity(key);

    //     assertEq(bidLiquidity, 12000 ether);
    //     assertEq(liquidity, 10000 ether);
    //     // assertEq(virtualOfferliquidity, 12000 ether); // 12000 or 2000 extra
    // }

    // function testForMutlipleSwapsInBothDirections() public {
    //     // positions were created in setup()
    //     addLiquidityViaHook(10000 ether, -24000, 24000);

    //     AttackerSwapTransaction(10 ether, true, false);
    //     UserSwapTransaction(100 ether, true, false);
    //     MockERC20(Currency.unwrap(currency0)).approve(
    //         address(swapRouter),
    //         10 ether
    //     );

    //     uint256 attackerSellAmount = MockERC20(Currency.unwrap(currency1))
    //         .balanceOf(address(attacker));

    //     vm.startPrank(attacker);
    //     MockERC20(Currency.unwrap(currency1)).approve(
    //         address(swapRouter),
    //         10 ether
    //     );
    //     AttackerSwapTransaction(attackerSellAmount, false, true);
    //     vm.stopPrank();

    //     uint256 attackerFinalAmount = MockERC20(Currency.unwrap(currency0))
    //         .balanceOf(address(attacker));
    //     console.log("attackerFinalAmount===");
    //     console.logUint(attackerFinalAmount);
    // }

    function addLiquidityViaHook(
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

        hook.addLiquidity(
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

    function testSrPoolInitialized() public {
        (Slot0 bid, Slot0 offer) = hook.getSrPoolSlot0(key);

        assertEq(bid.sqrtPriceX96(), SQRT_PRICE_1_1);
        assertEq(offer.sqrtPriceX96(), SQRT_PRICE_1_1);
    }

    function displayPoolLiq(
        PoolKey memory key
    )
        internal
        returns (
            uint128 bidLiq,
            uint128 offerLiq,
            uint128 vBLiq,
            uint128 vOLiq,
            Slot0 bid,
            Slot0 offer
        )
    {
        (uint128 bidLiq, uint128 offerLiq, uint128 vBLiq, uint128 vOLiq) = hook
            .getSrPoolLiquidity(key);
        console.log("Liquidity------");
        console.log(bidLiq);
        console.log(offerLiq);
        console.log(vBLiq);
        console.log(vOLiq);

        (Slot0 bid, Slot0 offer) = hook.getSrPoolSlot0(key);
        console.log("Pool SQRT ----");
        console.log(bid.sqrtPriceX96());
        console.log(offer.sqrtPriceX96());
        console.log("Pool Tick ----");
        console.logInt(bid.tick());
        console.logInt(offer.tick());

        return (bidLiq, offerLiq, vBLiq, vOLiq, bid, offer);
    }

    function calculateVirtualLiquidity(
        uint160 sqrtBidPriceX96,
        uint160 sqrtPriceStartX96,
        uint128 bidliquidity,
        bool roundup
    ) public returns (uint128 virtualOfferliquidity) {
        uint128 virtualOfferliquidity;
        virtualOfferliquidity =
            virtualOfferliquidity +
            uint128(
                SqrtPriceMath.getAmount0Delta(
                    sqrtBidPriceX96,
                    sqrtPriceStartX96,
                    bidliquidity,
                    roundup
                )
            );

        console.log("virtualOfferliquidity ---- Calculation");
        console.logUint(virtualOfferliquidity);

        return virtualOfferliquidity;
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

            displayPoolLiq(key);

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

            displayPoolLiq(key);

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

            displayPoolLiq(key);

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

            displayPoolLiq(key);

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

    function PrintingLiquidityPoolData() public {
        (
            uint128 bidLiquidity,
            uint128 liquidity,
            uint128 virtualBidLiquidity,
            uint128 virtualOfferliquidity
        ) = hook.getSrPoolLiquidity(key);
        console.log("Liquidity Infor");
        console.logUint(bidLiquidity);
        console.logUint(liquidity);
        console.logUint(virtualBidLiquidity);
        console.logUint(virtualOfferliquidity);
    }
}
