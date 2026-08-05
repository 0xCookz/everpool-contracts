// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
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
        require(wethSeed > 0, "seed=0");
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

        (uint256 amt0, uint256 amt1) =
            Currency.unwrap(c0) == token ? (SUPPLY, wethSeed) : (wethSeed, SUPPLY);

        // start the pool at the seed's own ratio, so both sides are used and the price isn't arbitrary
        poolManager.initialize(key, _priceFromAmounts(amt0, amt1));

        // move the seed assets to the vault, then let it add & lock the position (it owns positions)
        IERC20(token).transfer(address(vault), SUPPLY);
        IERC20(weth).transfer(address(vault), wethSeed);
        vault.seed(key, amt0, amt1);

        emit Launched(token, id, msg.sender, wethSeed);
    }

    /// @dev sqrtPriceX96 for a pool that will hold amt0 of currency0 and amt1 of currency1.
    ///      price = amt1/amt0 (currency1 per currency0); sqrtPriceX96 = sqrt(price) * 2**96.
    function _priceFromAmounts(uint256 amt0, uint256 amt1) internal pure returns (uint160) {
        return uint160(Math.sqrt(Math.mulDiv(amt1, 1 << 192, amt0)));
    }
}
