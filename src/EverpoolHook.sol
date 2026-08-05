// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseTestHooks} from "v4-core/src/test/BaseTestHooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

/// @title EverpoolHook
/// @notice Uniswap v4 hook that makes an Everpool pool's liquidity PERMANENT and PROTOCOL-OWNED:
///         - only allow-listed protocol contracts (Launcher / Compounder) may add liquidity;
///         - nobody, ever, may remove liquidity — the pool can only grow.
///
///         One hook instance serves every Everpool pool. Its *address* must encode the
///         BEFORE_ADD_LIQUIDITY and BEFORE_REMOVE_LIQUIDITY flags — mined via CREATE2 in the
///         deploy script (see `getHookPermissions`).
///
/// @dev    Prototype — not audited. The Liquidify-style platform fee cut is applied in the
///         Compounder (a % of collected fees goes to the treasury before the rest is re-pooled),
///         so this hook stays a minimal, auditable "lock".
contract EverpoolHook is BaseTestHooks {
    IPoolManager public immutable poolManager;
    address public owner;

    /// @notice Contracts allowed to add liquidity (the Launcher and the Compounder).
    mapping(address => bool) public authorized;

    error NotPoolManager();
    error NotOwner();
    error LiquidityLocked();        // outsiders cannot add liquidity
    error LiquidityIsPermanent();   // nobody can remove liquidity

    event AuthorizedSet(address indexed account, bool allowed);
    event OwnershipTransferred(address indexed from, address indexed to);

    constructor(IPoolManager _manager, address _owner) {
        poolManager = _manager;
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    function setAuthorized(address account, bool allowed) external onlyOwner {
        authorized[account] = allowed;
        emit AuthorizedSet(account, allowed);
    }

    function transferOwnership(address to) external onlyOwner {
        emit OwnershipTransferred(owner, to);
        owner = to;
    }

    /// @notice Permission flags this hook needs; used by the deploy script's HookMiner.
    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,      // gate: only protocol may add
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,   // gate: nobody may remove
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @dev Only the Launcher / Compounder may add liquidity. Everyone else just trades.
    ///      A zero/negative delta (fee-collect path) is not an add and is allowed through.
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) external view override onlyPoolManager returns (bytes4) {
        if (params.liquidityDelta > 0 && !authorized[sender]) revert LiquidityLocked();
        return IHooks.beforeAddLiquidity.selector;
    }

    /// @dev Liquidity is permanent — any removal (negative delta) is rejected.
    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) external pure override returns (bytes4) {
        if (params.liquidityDelta < 0) revert LiquidityIsPermanent();
        return IHooks.beforeRemoveLiquidity.selector;
    }
}
