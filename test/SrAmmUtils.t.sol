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

contract SrAmmUtils is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    SrAmmHook hook;
    PoolId poolId;

    address attacker;
    address user;
    address user2;
    address user3;

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

        deployCodeTo("SrAmmHook.sol:SrAmmHook", abi.encode(manager), flags);
        hook = SrAmmHook(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 100, tickSpacing, IHooks(hook));
        poolId = key.toId();
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
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        vm.deal(attacker, 1 ether);
        vm.deal(user, 1 ether);
        vm.deal(user2, 1 ether);
        vm.deal(user3, 1 ether);
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
        console.log(bidLiq);
        console.log(offerLiq);
        console.log(vBLiq);
        console.log(vOLiq);

        (Slot0 bid, Slot0 offer) = hook.getSrPoolSlot0(key);
        console.log(bid.sqrtPriceX96());
        console.log(offer.sqrtPriceX96());
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
        console.logUint(virtualOfferliquidity);

        return virtualOfferliquidity;
    }

    function AttackerSwapTransaction(
        uint256 amount,
        bool isZeroForOne,
        bool hasBalance,
        address userAddress
    ) public {
        if (isZeroForOne) {
            if (!hasBalance)
                fundCurrencyAndApproveRouter(userAddress, currency0, amount);
            vm.startPrank(userAddress);
            BalanceDelta swapDelta = swap(
                key,
                true, //zerForOne true (selling at bidPrice, right to left)
                -int256(amount), // negative number indicates exact input swap!
                ZERO_BYTES
            );
            vm.stopPrank();
        } else {
            if (!hasBalance) {
                fundCurrencyAndApproveRouter(userAddress, currency1, amount);
            }
            vm.startPrank(userAddress);
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
        uint256 swapRouterAmount,
        address userAddress,
        bool isZeroForOne
    ) public returns (uint256 balance) {
        vm.startPrank(userAddress);
        uint256 attackerSellAmount = MockERC20(
            Currency.unwrap(isZeroForOne ? currency1 : currency0)
        ).balanceOf(address(userAddress));
        MockERC20(Currency.unwrap(isZeroForOne ? currency1 : currency0))
            .approve(address(swapRouter), swapRouterAmount);
        AttackerSwapTransaction(attackerSellAmount, false, true, userAddress);
        vm.stopPrank();
        uint256 attackerFinalBalance = MockERC20(
            Currency.unwrap(isZeroForOne ? currency0 : currency1)
        ).balanceOf(address(userAddress));
        return attackerFinalBalance;
    }

    function userSwapTransaction(
        uint256 amount,
        bool isZeroForOne,
        bool hasBalance,
        address userAddress
    ) public {
        if (isZeroForOne) {
            if (!hasBalance) {
                fundCurrencyAndApproveRouter(userAddress, currency0, amount);
            }
            vm.startPrank(userAddress);

            BalanceDelta swapDelta = swap(
                key,
                true, //zerForOne true (selling at bidPrice, right to left)
                -int256(amount), // negative number indicates exact input swap!
                ZERO_BYTES
            );
            vm.stopPrank();
        } else {
            if (!hasBalance) {
                fundCurrencyAndApproveRouter(userAddress, currency1, amount);
            }
            vm.startPrank(userAddress);
            BalanceDelta swapDelta = swap(
                key,
                false, //oneForZero true (selling at offerPrice, left to right)
                -int256(amount), // negative number indicates exact input swap!
                ZERO_BYTES
            );
            vm.stopPrank();
        }
    }

    function userSellBackTheCurrency(
        uint256 swapRouterAmount,
        address userAddress,
        bool isZeroForOne
    ) public returns (uint256 balance) {
        vm.startPrank(userAddress);
        uint256 userSellAmount = MockERC20(
            Currency.unwrap(isZeroForOne ? currency1 : currency0)
        ).balanceOf(address(userAddress));
        MockERC20(Currency.unwrap(isZeroForOne ? currency1 : currency0))
            .approve(address(swapRouter), swapRouterAmount);

        userSwapTransaction(userSellAmount, !isZeroForOne, true, userAddress);

        vm.stopPrank();
        uint256 userFinalBalance = MockERC20(
            Currency.unwrap(isZeroForOne ? currency0 : currency1)
        ).balanceOf(address(userAddress));
        return userFinalBalance;
    }

    function sandwichAttackSwap(bool isZeroForOne) public {
        // trasfer token1 to attacker and user

        uint256 token0AttackerBeforeAmount = 10 ether;
        fundCurrencyAndApproveRouter(
            attacker,
            isZeroForOne ? currency0 : currency1,
            token0AttackerBeforeAmount
        );

        uint256 token0UserBeforeAmount = 100 ether;
        fundCurrencyAndApproveRouter(
            user,
            isZeroForOne ? currency0 : currency1,
            token0UserBeforeAmount
        );

        // Perform a test sandwich attack //
        {
            // ----attacker--- //
            console.log("attacker.......");
            vm.startPrank(attacker);

            //hookdata = abi.encode(attacker);
            int256 attackerBuy0Amount = -int256(token0AttackerBeforeAmount); // negative number indicates exact input swap!
            BalanceDelta swapDelta = swap(
                key,
                isZeroForOne ? true : false, //zerForOne true (selling at bidPrice, right to left)
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
                isZeroForOne ? true : false, //zerForOne true (selling at bidPrice, right to left)
                userBuyAmount,
                ZERO_BYTES
            );
            vm.stopPrank();

            // --- attacker --- //
            vm.startPrank(attacker);
            console.log("Attacker........");

            displayPoolLiq(key);

            // approve router to spend, as it needs to settle
            MockERC20(Currency.unwrap(isZeroForOne ? currency1 : currency0))
                .approve(address(swapRouter), 10 ether);

            // negative number indicates exact input swap!
            int256 attackerSellAmount = -int256(
                MockERC20(Currency.unwrap(isZeroForOne ? currency1 : currency0))
                    .balanceOf(address(attacker))
            );

            BalanceDelta swapDelta3 = swap(
                key,
                isZeroForOne ? false : true, //zerForOne false (buying at offerPrice, left to right)
                attackerSellAmount,
                ZERO_BYTES
            );
            vm.stopPrank();
        }
        // ------------------- //
    }

    // function SandwichAttackZeroToOneSwap() public {
    //     // trasfer token1 to attacker and user

    //     uint256 token0AttackerBeforeAmount = 10 ether;
    //     fundCurrencyAndApproveRouter(
    //         attacker,
    //         currency0,
    //         token0AttackerBeforeAmount
    //     );

    //     uint256 token0UserBeforeAmount = 100 ether;
    //     fundCurrencyAndApproveRouter(user, currency0, token0UserBeforeAmount);

    //     // Perform a test sandwich attack //
    //     {
    //         // ----attacker--- //
    //         console.log("attacker.......");
    //         vm.startPrank(attacker);

    //         //hookdata = abi.encode(attacker);
    //         int256 attackerBuy0Amount = -int256(token0AttackerBeforeAmount); // negative number indicates exact input swap!
    //         BalanceDelta swapDelta = swap(
    //             key,
    //             true, //zerForOne true (selling at bidPrice, right to left)
    //             attackerBuy0Amount,
    //             ZERO_BYTES
    //         );
    //         vm.stopPrank();

    //         // ----user--- //
    //         console.log("User.......");
    //         vm.startPrank(user);

    //         displayPoolLiq(key);

    //         int256 userBuyAmount = -int256(token0UserBeforeAmount); // negative number indicates exact input swap!
    //         BalanceDelta swapDelta2 = swap(
    //             key,
    //             true, //zerForOne true (selling at bidPrice, right to left)
    //             userBuyAmount,
    //             ZERO_BYTES
    //         );
    //         vm.stopPrank();

    //         // --- attacker --- //
    //         vm.startPrank(attacker);
    //         console.log("Attacker........");

    //         displayPoolLiq(key);

    //         // approve router to spend, as it needs to settle
    //         MockERC20(Currency.unwrap(currency1)).approve(
    //             address(swapRouter),
    //             10 ether
    //         );

    //         // negative number indicates exact input swap!
    //         int256 attackerSellAmount = -int256(
    //             MockERC20(Currency.unwrap(currency1)).balanceOf(
    //                 address(attacker)
    //             )
    //         );

    //         BalanceDelta swapDelta3 = swap(
    //             key,
    //             false, //zerForOne false (buying at offerPrice, left to right)
    //             attackerSellAmount,
    //             ZERO_BYTES
    //         );
    //         vm.stopPrank();
    //     }
    //     // ------------------- //
    // }

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
}
