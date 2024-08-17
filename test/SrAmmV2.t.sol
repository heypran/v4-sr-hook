// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SrAmmV2} from "../src/SrAmmV2.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract SrAmmV2Test is Test, Deployers, SrAmmV2 {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    address user;
    PoolId poolId;

    function setUp() public {
        Deployers.deployFreshManagerAndRouters();
        Deployers.deployMintAndApprove2Currencies();

        // Create the pool
        key = PoolKey(currency0, currency1, 100, 1, IHooks(address(0)));
        poolId = key.toId();
        // _initializePool(poolKey, 79228162514264337593543950336); // sqrtPriceX96 equivalent to 1.0 price
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(
                TickMath.minUsableTick(1),
                TickMath.maxUsableTick(1),
                10_000 ether, // 10000000000000000000000
                0
            ),
            ZERO_BYTES
        );
        // // Initialize the pool with a sqrtPrice
    }

    function testResetSlot() public {
        user = makeAddr("user");
        vm.deal(user, 1 ether);
        fundCurrencyAndApproveRouter(user, currency0, 10 ether);
        // 1. Ensure resetSlot is executed successfully the first time
        bool result = resetSlot(key);
        assertTrue(result, "Expected resetSlot to return true on first call");
        // 2. Check that the slot has been reset
        uint256 lastBlock = _lastBlock[key.toId()];
        assertEq(
            lastBlock,
            block.number,
            "Expected _lastBlock to be updated to current block"
        );

        vm.startPrank(user);
        BalanceDelta swapDelta = swap(
            key,
            true, //zerForOne true (selling at bidPrice, right to left)
            -int256(1 ether), // negative number indicates exact input swap!
            ZERO_BYTES
        );
        vm.stopPrank();

        // 4. Call resetSlot again within the same block; expect it to return false
        result = resetSlot(key);
        assertFalse(
            result,
            "Expected resetSlot to return false within the same block"
        );

        // 5. Advance one block and call resetSlot again; expect it to return true
        vm.roll(block.number + 1); // Advance one block
        result = resetSlot(key);
        assertTrue(
            result,
            "Expected resetSlot to return true after advancing blocks"
        );

        // 6. Verify that _lastBlock is updated correctly
        lastBlock = _lastBlock[key.toId()];
        assertEq(
            lastBlock,
            block.number,
            "Expected _lastBlock to update to the new block number"
        );
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
}
