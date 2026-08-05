// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EverpoolToken} from "./EverpoolToken.sol";

interface IEverpoolVault {
    function seed(PoolKey calldata key, uint256 amt0, uint256 amt1) external;
}

/// @title EverpoolLauncher
/// @notice One-transaction launch: deploy a fixed-supply token, open a Uniswap v4 pool paired with
///         WETH under the EverpoolHook, and hand the assets to the vault (Compounder) which seeds a
///         full-range position that is **locked forever** (the hook forbids removal) and grows it.
///
/// @dev    Prototype — not audited. Testnet only. Initial price is a fixed 1:1 placeholder.
contract EverpoolLauncher {
    using PoolIdLibrary for PoolKey;

    IPoolManager public immutable poolManager;
    IHooks public immutable hook;
    address public immutable weth;
    IEverpoolVault public immutable vault;

    uint24 public constant FEE = 3000;          // 0.30%
    int24 public constant TICK_SPACING = 60;
    uint256 public constant SUPPLY = 1_000_000_000e18;   // 1,000,000,000 tokens
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    event Launched(address indexed token, PoolId indexed poolId, address indexed creator, uint256 wethSeed);

    constructor(IPoolManager _poolManager, IHooks _hook, address _weth, IEverpoolVault _vault) {
        poolManager = _poolManager;
        hook = _hook;
        weth = _weth;
        vault = _vault;
    }

    /// @notice Launch a new token and seed its locked pool.
    /// @param wethSeed WETH pulled from the caller to seed the other side of the pool
    function launch(string calldata name, string calldata symbol, uint256 wethSeed)
        external
        returns (address token, PoolId id)
    {
        IERC20(weth).transferFrom(msg.sender, address(this), wethSeed);

        EverpoolToken t = new EverpoolToken(name, symbol, SUPPLY, address(this));
        token = address(t);

        // v4 requires currency0 < currency1
        (Currency c0, Currency c1) = token < weth
            ? (Currency.wrap(token), Currency.wrap(weth))
            : (Currency.wrap(weth), Currency.wrap(token));

        PoolKey memory key =
            PoolKey({currency0: c0, currency1: c1, fee: FEE, tickSpacing: TICK_SPACING, hooks: hook});
        id = key.toId();

        poolManager.initialize(key, SQRT_PRICE_1_1);

        // move the seed assets to the vault, then let it add & lock the position (it owns positions)
        uint256 amt0;
        uint256 amt1;
        if (Currency.unwrap(c0) == token) {
            amt0 = SUPPLY;
            amt1 = wethSeed;
        } else {
            amt0 = wethSeed;
            amt1 = SUPPLY;
        }
        IERC20(token).transfer(address(vault), SUPPLY);
        IERC20(weth).transfer(address(vault), wethSeed);
        vault.seed(key, amt0, amt1);

        emit Launched(token, id, msg.sender, wethSeed);
    }
}
