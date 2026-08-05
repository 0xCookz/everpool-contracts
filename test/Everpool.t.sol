// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {HookMiner} from "v4-periphery/test/shared/HookMiner.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {EverpoolHook} from "../src/EverpoolHook.sol";
import {EverpoolLauncher, IEverpoolVault} from "../src/EverpoolLauncher.sol";
import {EverpoolCompounder} from "../src/EverpoolCompounder.sol";

contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract EverpoolTest is Test {
    using StateLibrary for IPoolManager;

    PoolManager manager;
    PoolSwapTest swapRouter;
    PoolModifyLiquidityTest liqRouter;
    MockWETH weth;
    EverpoolHook hook;
    EverpoolLauncher launcher;
    EverpoolCompounder compounder;

    address treasury = address(0xBEEF);

    function setUp() public {
        manager = new PoolManager(address(this));
        swapRouter = new PoolSwapTest(manager);
        liqRouter = new PoolModifyLiquidityTest(manager);
        weth = new MockWETH();

        // mine an address that carries the two liquidity-gating flags, then CREATE2-deploy the hook.
        uint160 flags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG);
        bytes memory args = abi.encode(IPoolManager(address(manager)), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(EverpoolHook).creationCode, args);
        hook = new EverpoolHook{salt: salt}(IPoolManager(address(manager)), address(this));
        require(address(hook) == hookAddr, "hook addr mismatch");

        compounder = new EverpoolCompounder(manager, treasury, 1000);
        launcher = new EverpoolLauncher(manager, IHooks(address(hook)), address(weth), IEverpoolVault(address(compounder)));
        compounder.setLauncher(address(launcher));

        hook.setAuthorized(address(compounder), true);
    }

    function _launch(uint256 seed) internal returns (address token, PoolId id, PoolKey memory key) {
        weth.mint(address(this), seed);
        weth.approve(address(launcher), type(uint256).max);
        (token, id) = launcher.launch("Everpool", "POOL", seed);
        key = compounder.poolKey(id);
    }

    /// The pool is created and seeded with liquidity.
    function test_launch_seeds_liquidity() public {
        (address token, PoolId id,) = _launch(10 ether);
        assertTrue(token != address(0), "token deployed");
        assertGt(StateLibrary.getLiquidity(manager, id), 0, "pool has liquidity");
    }

    /// Nobody can remove liquidity — the pool can only grow.
    function test_liquidity_is_permanent() public {
        (, , PoolKey memory key) = _launch(10 ether);
        int24 tl = TickMath.minUsableTick(key.tickSpacing);
        int24 tu = TickMath.maxUsableTick(key.tickSpacing);
        vm.expectRevert(); // EverpoolHook.LiquidityIsPermanent
        liqRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: tl, tickUpper: tu, liquidityDelta: -1, salt: bytes32(0)}),
            ""
        );
    }

    /// Outsiders cannot add liquidity either (protocol-owned).
    function test_outsider_cannot_add_liquidity() public {
        (, , PoolKey memory key) = _launch(10 ether);
        int24 tl = TickMath.minUsableTick(key.tickSpacing);
        int24 tu = TickMath.maxUsableTick(key.tickSpacing);
        vm.expectRevert(); // EverpoolHook.LiquidityLocked
        liqRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: tl, tickUpper: tu, liquidityDelta: 1e18, salt: bytes32(0)}),
            ""
        );
    }

    /// Trading generates fees; compound() folds them back in and pays the platform cut.
    function test_compound_grows_pool() public {
        (address token, PoolId id, PoolKey memory key) = _launch(50 ether);
        uint128 lBefore = StateLibrary.getLiquidity(manager, id);

        // buy the token with WETH to generate fees (swap WETH -> token)
        bool wethIsZero = Currency.unwrap(key.currency0) == address(weth);
        weth.mint(address(this), 20 ether);
        weth.approve(address(swapRouter), type(uint256).max);
        // also approve the token side in case of multi-hop settle
        ERC20(token).approve(address(swapRouter), type(uint256).max);

        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: wethIsZero,
                amountSpecified: -int256(5 ether), // exact-in 5 WETH
                sqrtPriceLimitX96: wethIsZero ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );

        compounder.compound(id);

        uint128 lAfter = StateLibrary.getLiquidity(manager, id);
        assertGt(lAfter, lBefore, "pool grew after compound");
        // platform got a cut of the WETH fees
        assertGt(weth.balanceOf(treasury), 0, "treasury received platform cut");
    }
}
