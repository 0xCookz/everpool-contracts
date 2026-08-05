// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EverpoolToken} from "./EverpoolToken.sol";

interface ILiquidityLauncherV3 {
    function launchAndLock(address token, uint256 amount, address feeRecipient) external;
}

/// @title EverpoolPoolsLauncher
/// @notice Launches GENUINE pools.trade tokens: deploys a fixed-supply ERC20 and launches it through
///         pools.trade's official **LiquidityLauncherV3** (Uniswap Liquidity Launchpad on Robinhood
///         Chain) — a single-sided, permanently-locked Uniswap v4 pool. Trading fees route to
///         pools.trade's **CompoundingClaimRecipient**, so they auto-compound back into the pool.
///         No WETH seed required — launching is free (just gas). One transaction for the creator.
/// @dev    Prototype — not audited. Mainnet only (LiquidityLauncherV3 is not on testnet).
contract EverpoolPoolsLauncher {
    ILiquidityLauncherV3 public immutable launcher;    // pools.trade LiquidityLauncherV3
    address public immutable feeRecipient;             // pools.trade CompoundingClaimRecipient
    uint256 public constant SUPPLY = 1_000_000_000e18; // 1,000,000,000 tokens

    uint256 public poolsLaunched;

    event Launched(address indexed token, address indexed creator, string name, string symbol);

    constructor(ILiquidityLauncherV3 _launcher, address _feeRecipient) {
        launcher = _launcher;
        feeRecipient = _feeRecipient;
    }

    /// @notice Deploy a token and launch it on pools.trade. Returns the new token address.
    function launch(string calldata name, string calldata symbol) external returns (address token) {
        EverpoolToken t = new EverpoolToken(name, symbol, SUPPLY, address(this));
        token = address(t);
        IERC20(token).approve(address(launcher), SUPPLY);
        launcher.launchAndLock(token, SUPPLY, feeRecipient);
        unchecked { poolsLaunched++; }
        emit Launched(token, msg.sender, name, symbol);
    }
}
