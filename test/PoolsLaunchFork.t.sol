// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EverpoolPoolsLauncher, ILiquidityLauncherV3} from "../src/EverpoolPoolsLauncher.sol";

/// @notice Fork test against pools.trade's REAL LiquidityLauncherV3 on Robinhood Chain mainnet.
///         Run: forge test --fork-url https://rpc.mainnet.chain.robinhood.com --match-path test/PoolsLaunchFork.t.sol -vvv
contract PoolsLaunchForkTest is Test {
    address constant LAUNCHER_V3 = 0xE8DCF8898D621C7F40e182eE5Ce9C8715C4F7894; // pools.trade LiquidityLauncherV3
    address constant COMPOUNDING = 0xf9526Dd3361fe0ba6b7a99533ed471D3E808E99a; // CompoundingClaimRecipient

    EverpoolPoolsLauncher ep;
    bool forked;

    function setUp() public {
        if (LAUNCHER_V3.code.length == 0) return;
        forked = true;
        ep = new EverpoolPoolsLauncher(ILiquidityLauncherV3(LAUNCHER_V3), COMPOUNDING);
    }

    function test_launch_a_poolstrade_token() public {
        if (!forked) { vm.skip(true); return; }
        address token = ep.launch("Everpool", "POOL");
        assertTrue(token != address(0), "token deployed");
        assertEq(IERC20(token).totalSupply(), 1_000_000_000e18, "fixed supply");
        // after launch, the supply is single-sided in the locked pool, not held by our launcher
        assertEq(IERC20(token).balanceOf(address(ep)), 0, "supply moved into the pool");
        assertEq(ep.poolsLaunched(), 1, "counter");
    }
}
