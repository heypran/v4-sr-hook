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

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();
        Deployers.deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
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
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(
                TickMath.minUsableTick(60),
                TickMath.maxUsableTick(60),
                10_000 ether,
                0
            ),
            ZERO_BYTES
        );
    }

    function testSrPoolInitialized() public {
        assertEq(hook.beforeAddLiquidityCount(poolId), 1);
        assertEq(hook.beforeRemoveLiquidityCount(poolId), 0);

        assertEq(hook.beforeSwapCount(poolId), 0);
        assertEq(hook.afterSwapCount(poolId), 0);

        (Slot0 bid, Slot0 offer) = hook.getSrPoolSlot0(key);

        assertEq(bid.sqrtPriceX96(), SQRT_PRICE_1_1);
        assertEq(offer.sqrtPriceX96(), SQRT_PRICE_1_1);
    }

    function testSwapOnSrPool() public {
        // positions were created in setup()

        // Perform a test swap //
        address user = makeAddr("user");
        uint256 token1AttackerBeforeAmount = 1 ether;
        MockERC20(Currency.unwrap(currency1)).transfer(
            address(user),
            token1AttackerBeforeAmount
        );

        vm.startPrank(user);

        // approve router
        MockERC20(Currency.unwrap(currency1)).approve(
            address(swapRouter),
            1 ether
        );
        // approve hook to spend, as it needs to settle / bad UI/UX (TODO: find a workaround)
        // MockERC20(Currency.unwrap(currency1)).approve(address(hook), 1 ether);

        bool zeroForOne = false;
        // negative number indicates exact input swap!
        int256 amountSpecified = -1e18;

        bytes memory hookdata = abi.encode(address(user));
        BalanceDelta swapDelta = swap(
            key,
            zeroForOne,
            amountSpecified,
            hookdata
        );
        vm.stopPrank();
        // ------------------- //

        assertEq(int256(swapDelta.amount1()), amountSpecified);

        uint256 userBalance0 = MockERC20(Currency.unwrap(currency0)).balanceOf(
            address(user)
        );
        assertGt(userBalance0, 0.99e17);

        assertEq(hook.beforeSwapCount(poolId), 1);
        assertEq(hook.afterSwapCount(poolId), 0);
    }
}
