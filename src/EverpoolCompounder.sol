// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title EverpoolCompounder (the vault)
/// @notice Owns every Everpool pool's single, full-range, permanent liquidity position, and is the
///         one entity that ever modifies it — so fees accrue to *its* position and it can fold them
///         back in. It (1) seeds the position at launch and (2) compounds fees on a ~10-min cadence:
///         collect accrued fees -> send a configurable platform cut to the treasury (Liquidify-style)
///         -> re-add the rest as locked liquidity. `compound()` is permissionless (keeper or public).
///
/// @dev    Prototype — not audited. v1 re-adds collected fees directly; an explicit swap-to-balance
///         ("swap half") is a polish step. Dust remains for the next cycle.
contract EverpoolCompounder is IUnlockCallback, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using BalanceDeltaLibrary for BalanceDelta;

    uint8 internal constant ACTION_SEED = 0;
    uint8 internal constant ACTION_COMPOUND = 1;
    uint16 public constant MAX_PLATFORM_FEE_BPS = 2000; // hard cap 20%

    IPoolManager public immutable poolManager;
    address public owner;
    address public launcher;                 // the only address allowed to seed new pools
    address public treasury;
    uint16 public platformFeeBps;            // e.g. 1000 = 10% (Liquidify-style)

    // live protocol stats (read on-chain by the website)
    uint256 public poolsLaunched;
    uint256 public cyclesRun;

    mapping(PoolId => PoolKey) internal _keyOf;

    event Seeded(PoolId indexed poolId, uint128 liquidity);
    event Compounded(PoolId indexed poolId, uint128 liquidityAdded, uint256 cut0, uint256 cut1);
    event LauncherSet(address launcher);
    event ConfigSet(address treasury, uint16 platformFeeBps);

    error NotPoolManager();
    error NotOwner();
    error NotLauncher();
    error FeeTooHigh();
    error AlreadyRegistered();
    error UnknownPool();

    constructor(IPoolManager _poolManager, address _treasury, uint16 _platformFeeBps) {
        if (_platformFeeBps > MAX_PLATFORM_FEE_BPS) revert FeeTooHigh();
        poolManager = _poolManager;
        owner = msg.sender;
        treasury = _treasury;
        platformFeeBps = _platformFeeBps;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function setLauncher(address _launcher) external onlyOwner {
        launcher = _launcher;
        emit LauncherSet(_launcher);
    }

    function setConfig(address _treasury, uint16 _platformFeeBps) external onlyOwner {
        if (_platformFeeBps > MAX_PLATFORM_FEE_BPS) revert FeeTooHigh();
        treasury = _treasury;
        platformFeeBps = _platformFeeBps;
        emit ConfigSet(_treasury, _platformFeeBps);
    }

    function transferOwnership(address to) external onlyOwner {
        owner = to;
    }

    function poolKey(PoolId id) external view returns (PoolKey memory) {
        return _keyOf[id];
    }

    /// @notice Seed a newly launched pool's locked position. The Launcher transfers the token supply
    ///         and the WETH seed to this contract first, then calls this.
    function seed(PoolKey calldata key, uint256 amt0, uint256 amt1) external nonReentrant {
        if (msg.sender != launcher) revert NotLauncher();
        PoolId id = key.toId();
        if (Currency.unwrap(_keyOf[id].currency0) != address(0)) revert AlreadyRegistered();
        _keyOf[id] = key;
        unchecked { poolsLaunched++; }
        poolManager.unlock(abi.encode(ACTION_SEED, key, amt0, amt1));
        emit Seeded(id, 0);
    }

    /// @notice Collect accrued fees for a pool and fold them back into its locked liquidity.
    function compound(PoolId id) external nonReentrant returns (uint256 added) {
        PoolKey memory key = _keyOf[id];
        if (Currency.unwrap(key.currency0) == address(0)) revert UnknownPool();
        unchecked { cyclesRun++; }
        bytes memory ret = poolManager.unlock(abi.encode(ACTION_COMPOUND, key, uint256(0), uint256(0)));
        added = abi.decode(ret, (uint256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        (uint8 action, PoolKey memory key,,) = abi.decode(data, (uint8, PoolKey, uint256, uint256));

        int24 tickLower = TickMath.minUsableTick(key.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        if (action == ACTION_SEED) {
            (, , uint256 amt0, uint256 amt1) = abi.decode(data, (uint8, PoolKey, uint256, uint256));
            uint128 liquidity = _addLiquidity(key, tickLower, tickUpper, amt0, amt1);
            return abi.encode(uint256(liquidity));
        }

        // ACTION_COMPOUND: realize accrued fees (liquidityDelta = 0) on our own position.
        (BalanceDelta feeDelta,) = poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: 0, salt: bytes32(0)}),
            ""
        );
        uint256 fee0 = feeDelta.amount0() > 0 ? uint256(uint128(feeDelta.amount0())) : 0;
        uint256 fee1 = feeDelta.amount1() > 0 ? uint256(uint128(feeDelta.amount1())) : 0;
        if (fee0 > 0) poolManager.take(key.currency0, address(this), fee0);
        if (fee1 > 0) poolManager.take(key.currency1, address(this), fee1);

        uint256 cut0 = (fee0 * platformFeeBps) / 10_000;
        uint256 cut1 = (fee1 * platformFeeBps) / 10_000;
        if (cut0 > 0) key.currency0.transfer(treasury, cut0);
        if (cut1 > 0) key.currency1.transfer(treasury, cut1);

        // fees arrive one-sided; swap ~half of the surplus so both sides are non-zero ("swap half")
        (uint256 add0, uint256 add1) = _balance(key, fee0 - cut0, fee1 - cut1);
        uint128 added = _addLiquidity(key, tickLower, tickUpper, add0, add1);
        emit Compounded(key.toId(), added, cut0, cut1);
        return abi.encode(uint256(added));
    }

    /// @dev Add `amt0/amt1` (already held by this contract) as full-range liquidity, settling the debt.
    function _addLiquidity(PoolKey memory key, int24 tickLower, int24 tickUpper, uint256 amt0, uint256 amt1)
        internal
        returns (uint128 liquidity)
    {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amt0,
            amt1
        );
        if (liquidity == 0) return 0;

        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(uint256(liquidity)),
                salt: bytes32(0)
            }),
            ""
        );
        int128 d0 = delta.amount0();
        int128 d1 = delta.amount1();
        if (d0 < 0) _settle(key.currency0, uint256(uint128(-d0)));
        if (d1 < 0) _settle(key.currency1, uint256(uint128(-d1)));
    }

    /// @dev Swap half of a one-sided balance into the other token so a full-range add can use both.
    function _balance(PoolKey memory key, uint256 add0, uint256 add1) internal returns (uint256, uint256) {
        if (add0 > 0 && add1 == 0) {
            uint256 half = add0 / 2;
            if (half == 0) return (add0, add1);
            BalanceDelta sd = poolManager.swap(
                key,
                IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -int256(half), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
                ""
            );
            if (sd.amount0() < 0) _settle(key.currency0, uint256(uint128(-sd.amount0())));
            uint256 out1 = sd.amount1() > 0 ? uint256(uint128(sd.amount1())) : 0;
            if (out1 > 0) poolManager.take(key.currency1, address(this), out1);
            return (add0 - half, out1);
        } else if (add1 > 0 && add0 == 0) {
            uint256 half = add1 / 2;
            if (half == 0) return (add0, add1);
            BalanceDelta sd = poolManager.swap(
                key,
                IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -int256(half), sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1}),
                ""
            );
            if (sd.amount1() < 0) _settle(key.currency1, uint256(uint128(-sd.amount1())));
            uint256 out0 = sd.amount0() > 0 ? uint256(uint128(sd.amount0())) : 0;
            if (out0 > 0) poolManager.take(key.currency0, address(this), out0);
            return (out0, add1 - half);
        }
        return (add0, add1);
    }

    function _settle(Currency currency, uint256 amount) internal {
        poolManager.sync(currency);
        currency.transfer(address(poolManager), amount);
        poolManager.settle();
    }
}
