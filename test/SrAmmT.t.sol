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

    int24 tickSpacing = 1;

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


    function displayPoolLiq(PoolKey memory key) internal {
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

//ZEROFORONE CASES
 // 1. Testing liquidity changes for simple attack swap from zero for one. This invloves active liquidity remains unchanged
 function testSrSwapOnSrPoolActiveLiquidityRangeNoChangesZF1() public {
        // positions were created in setup()

         addLiquidityViaHook(
            1000 ether,
            -3000,
            3000
            );

            addLiquidityViaHook(
            1000 ether,
          -6000,
           -3000
        );

        displayPoolLiq(key);

       SandwichAttackZeroToOneSwap();

        console.log("After Swap SQRT Prices and ticks");
        (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);
        console.log(bid2.sqrtPriceX96());
        console.log(offer2.sqrtPriceX96());
        console.logInt(bid2.tick());
        console.logInt(offer2.tick());

        (uint128 bidLiquidity, uint128 liquidity, uint128 virtualBidLiquidity, uint128  virtualOfferliquidity) = hook.getSrPoolLiquidity(key);
        console.log("Liquidity data");
        console.logUint(bidLiquidity);
        console.logUint(liquidity);
        console.logUint(virtualBidLiquidity);
        console.logUint(virtualOfferliquidity);

        assertEq(bidLiquidity, 1000 ether);
        assertEq(liquidity, 1000 ether);
        assertEq(virtualBidLiquidity, 0 ether);
        assertEq(virtualOfferliquidity, 0 ether);
    }
//2. Testing liquidity changes for simple attack swap from zero for one. This invloves active liquidity changes
 function testSrSwapOnSrPoolActiveLiquidityRangeChangesZF1() public {
        // positions were created in setup()

         addLiquidityViaHook(
            1000 ether,
            -1800,
            1800
            );

            addLiquidityViaHook(
            1000 ether,
          -6000,
           -1800
        );

        displayPoolLiq(key);

       SandwichAttackZeroToOneSwap();

        console.log("After Swap SQRT Prices and ticks");
        (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);
        console.log(bid2.sqrtPriceX96());
        console.log(offer2.sqrtPriceX96());
        console.logInt(bid2.tick());
        console.logInt(offer2.tick());

        (uint128 bidLiquidity, uint128 liquidity, uint128 virtualBidLiquidity, uint128  virtualOfferliquidity) = hook.getSrPoolLiquidity(key);
        console.log("Liquidity data");
        console.logUint(bidLiquidity);
        console.logUint(liquidity);
        console.logUint(virtualBidLiquidity);
        console.logUint(virtualOfferliquidity);

        assertEq(bidLiquidity, 1000 ether);
        assertEq(liquidity, 1000 ether);
        assertEq(virtualBidLiquidity, 0 ether);
        assertEq(virtualOfferliquidity, 1000 ether);
    }

// 3. Testing in Overlapped liquidities
// To check whether the active liqudity range amount changes based on the tick movement when it moves out of some liquidity ranges.

function testSrSwapOnSrPoolMultipleOverlappedLiquidityZF1() public {
        // positions were created in setup()

         addLiquidityViaHook(
            10000 ether,
            -3000,
            3000
        );
        addLiquidityViaHook(
            1000 ether,
            -60,
            60
        );

        addLiquidityViaHook(
            1000 ether,
           2000,
           6000
        );

        addLiquidityViaHook(
            1000 ether,
            -24000,
            -12000
        );

        addLiquidityViaHook(
            1000 ether,
            -120,
            120
        );

        displayPoolLiq(key);


       (uint128 bidLiquidityBefore, uint128 liquidityBefore, uint128 virtualBidLiquidityBefore, uint128  virtualOfferliquidityBefore) = hook.getSrPoolLiquidity(key);
        console.log("Liquidity data Before");

        console.logUint(bidLiquidityBefore);
        console.logUint(liquidityBefore);
        assertEq(bidLiquidityBefore, 12000 ether);
        assertEq(liquidityBefore, 12000 ether);

       SandwichAttackZeroToOneSwap();

        console.log("After Swap SQRT Prices and ticks");
        (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);
        console.log(bid2.sqrtPriceX96());
        console.log(offer2.sqrtPriceX96());
        console.logInt(bid2.tick());
        console.logInt(offer2.tick());

        (uint128 bidLiquidity, uint128 liquidity, uint128 virtualBidLiquidity, uint128  virtualOfferliquidity) = hook.getSrPoolLiquidity(key);
        console.log("Liquidity data");
        console.logUint(bidLiquidity);
        console.logUint(liquidity);
        console.logUint(virtualBidLiquidity);
        console.logUint(virtualOfferliquidity);

        assertEq(bidLiquidity, 10000 ether);
        assertEq(liquidity, 12000 ether);
        // assertEq(virtualOfferliquidity, 12000 ether); // 12000 or 2000 extra
    }
    
   
   //ONEFORZERO CASES
   // 1. Testing liquidity changes for simple attack swap from zero for one. This invloves active liquidity remains unchanged
function testSrSwapOnSrPoolActiveLiquidityRangeNoChanges1FZ() public {
        // positions were created in setup()

         addLiquidityViaHook(
            1000 ether,
            -3000,
            3000
            );

            addLiquidityViaHook(
            1000 ether,
            3000,
            6000
        );

        displayPoolLiq(key);

       SandwichAttackOneToZeroSwap();

        console.log("After Swap SQRT Prices and ticks");
        (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);
        console.log(bid2.sqrtPriceX96());
        console.log(offer2.sqrtPriceX96());
        console.logInt(bid2.tick());
        console.logInt(offer2.tick());

        (uint128 bidLiquidity, uint128 liquidity, uint128 virtualBidLiquidity, uint128  virtualOfferliquidity) = hook.getSrPoolLiquidity(key);
        console.log("Liquidity data");
        console.logUint(bidLiquidity);
        console.logUint(liquidity);
        console.logUint(virtualBidLiquidity);
        console.logUint(virtualOfferliquidity);

        assertEq(bidLiquidity, 1000 ether);
        assertEq(liquidity, 1000 ether);
        assertEq(virtualBidLiquidity, 0 ether);
        assertEq(virtualOfferliquidity, 0 ether);
    }

       // 2. Testing liquidity changes for simple attack swap from zero for one. This invloves active liquidity changes
function testSrSwapOnSrPoolActiveLiquidityRangeChanges1FZ() public {
        // positions were created in setup()

         addLiquidityViaHook(
            1000 ether,
            -1800,
            1800
            );

            addLiquidityViaHook(
            1000 ether,
            1800,
            6000
        );

        displayPoolLiq(key);

       SandwichAttackOneToZeroSwap();

        console.log("After Swap SQRT Prices and ticks");
        (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);
        console.log(bid2.sqrtPriceX96());
        console.log(offer2.sqrtPriceX96());
        console.logInt(bid2.tick());
        console.logInt(offer2.tick());

        (uint128 bidLiquidity, uint128 liquidity, uint128 virtualBidLiquidity, uint128  virtualOfferliquidity) = hook.getSrPoolLiquidity(key);
        console.log("Liquidity data");
        console.logUint(bidLiquidity);
        console.logUint(liquidity);
        console.logUint(virtualBidLiquidity);
        console.logUint(virtualOfferliquidity);

        assertEq(bidLiquidity, 1000 ether);
        assertEq(liquidity, 1000 ether);
        assertEq(virtualBidLiquidity, 1000 ether);
        assertEq(virtualOfferliquidity, 0 ether);
    }


// 3. Testing in Overlapped liquidities
// To check whether the active liqudity range amount changes based on the tick movement when it moves out of some liquidity ranges.

function testSrSwapOnSrPoolMultipleOverlappedLiquidity1FZ() public {
        // positions were created in setup()

         addLiquidityViaHook(
            10000 ether,
            -3000,
            3000
        );
        addLiquidityViaHook(
            1000 ether,
            -60,
            60
        );

        addLiquidityViaHook(
            1000 ether,
           -6000,
           -2000
        );

        addLiquidityViaHook(
            1000 ether,
            12000,
            24000
        );

        addLiquidityViaHook(
            1000 ether,
            -120,
            120
        );

        displayPoolLiq(key);


       (uint128 bidLiquidityBefore, uint128 liquidityBefore, uint128 virtualBidLiquidityBefore, uint128  virtualOfferliquidityBefore) = hook.getSrPoolLiquidity(key);
        console.log("Liquidity data Before");

        console.logUint(bidLiquidityBefore);
        console.logUint(liquidityBefore);
        assertEq(bidLiquidityBefore, 12000 ether);
        assertEq(liquidityBefore, 12000 ether);

       SandwichAttackOneToZeroSwap();

        console.log("After Swap SQRT Prices and ticks");
        (Slot0 bid2, Slot0 offer2) = hook.getSrPoolSlot0(key);
        console.log(bid2.sqrtPriceX96());
        console.log(offer2.sqrtPriceX96());
        console.logInt(bid2.tick());
        console.logInt(offer2.tick());

        (uint128 bidLiquidity, uint128 liquidity, uint128 virtualBidLiquidity, uint128  virtualOfferliquidity) = hook.getSrPoolLiquidity(key);
        console.log("Liquidity data");
        console.logUint(bidLiquidity);
        console.logUint(liquidity);
        console.logUint(virtualBidLiquidity);
        console.logUint(virtualOfferliquidity);

        assertEq(bidLiquidity, 12000 ether);
        assertEq(liquidity, 10000 ether);
        // assertEq(virtualOfferliquidity, 12000 ether); // 12000 or 2000 extra
    }



   // Liquidity after buy order once sandwich attack taken places in zeroForOne case


    // 139014082579086214

    // Check if liquidity is handled correctly for OneForZero

    // Check the behaviour is correct in case of zeroForOne

    // Check if liquidity is handled correctly for zeroForOne

    // Check if liquidity is handled correctly for zeroForOne
}
