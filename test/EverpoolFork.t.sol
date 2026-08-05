// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {HookMiner} from "v4-periphery/test/shared/HookMiner.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {EverpoolHook} from "../src/EverpoolHook.sol";
import {EverpoolLauncher, IEverpoolVault} from "../src/EverpoolLauncher.sol";
import {EverpoolCompounder} from "../src/EverpoolCompounder.sol";

/// @notice Fork test against the REAL Uniswap v4 deployed on Robinhood Chain mainnet.
///         Run:  forge test --fork-url https://rpc.mainnet.chain.robinhood.com --match-path test/EverpoolFork.t.sol -vv
///         Self-gates: if not run on a fork (no PoolManager bytecode), all tests skip.
contract EverpoolForkTest is Test {
    // Robinhood Chain mainnet (4663)
    IPoolManager constant MANAGER = IPoolManager(0x8366a39CC670B4001A1121B8F6A443A643e40951);
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;

    PoolSwapTest swapRouter;
    EverpoolHook hook;
    EverpoolLauncher launcher;
    EverpoolCompounder compounder;
    address treasury = address(0xBEEF);
    bool forked;

    function setUp() public {
        if (address(MANAGER).code.length == 0) return; // not on a fork -> skip
        forked = true;

        swapRouter = new PoolSwapTest(MANAGER);

        uint160 flags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG);
        bytes memory args = abi.encode(MANAGER, address(this));
        (address hookAddr, bytes32 salt) = HookMiner.find(address(this), flags, type(EverpoolHook).creationCode, args);
        hook = new EverpoolHook{salt: salt}(MANAGER, address(this));
        require(address(hook) == hookAddr, "hook addr");

        compounder = new EverpoolCompounder(MANAGER, treasury, 1000);
        launcher = new EverpoolLauncher(MANAGER, IHooks(address(hook)), WETH, IEverpoolVault(address(compounder)));
        compounder.setLauncher(address(launcher));
        hook.setAuthorized(address(compounder), true);
    }

    /// End-to-end on real v4: launch, lock, trade, compound -> pool grows.
    function test_fork_launch_trade_compound() public {
        if (!forked) {
            vm.skip(true);
            return;
        }

        // fund with real WETH
        deal(WETH, address(this), 100 ether);
        IERC20(WETH).approve(address(launcher), type(uint256).max);

        (address token, PoolId id) = launcher.launch("Everpool", "POOL", 20 ether);
        PoolKey memory key = compounder.poolKey(id);
        uint128 lBefore = StateLibrary.getLiquidity(MANAGER, id);
        assertGt(lBefore, 0, "seeded");

        // trade to generate fees
        bool wethIsZero = Currency.unwrap(key.currency0) == WETH;
        deal(WETH, address(this), 10 ether);
        IERC20(WETH).approve(address(swapRouter), type(uint256).max);
        IERC20(token).approve(address(swapRouter), type(uint256).max);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: wethIsZero,
                amountSpecified: -int256(3 ether),
                sqrtPriceLimitX96: wethIsZero ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );

        compounder.compound(id);

        assertGt(StateLibrary.getLiquidity(MANAGER, id), lBefore, "pool grew on REAL v4");
        assertGt(IERC20(WETH).balanceOf(treasury), 0, "treasury cut");
    }
}
