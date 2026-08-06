// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EverpoolBurnVault} from "../src/EverpoolBurnVault.sol";
import {EverpoolToken} from "../src/EverpoolToken.sol";
import {EverpoolPoolsLauncher, ILiquidityLauncherV3} from "../src/EverpoolPoolsLauncher.sol";

contract BurnVaultTest is Test {
    EverpoolBurnVault vault;

    function setUp() public {
        vault = new EverpoolBurnVault();
    }

    function test_burn_token_to_dead() public {
        EverpoolToken t = new EverpoolToken("Burn", "BURN", 1000e18, address(vault));
        assertEq(t.balanceOf(address(vault)), 1000e18);
        vault.burn(address(t));
        assertEq(t.balanceOf(address(vault)), 0, "vault emptied");
        assertEq(t.balanceOf(vault.DEAD()), 1000e18, "token burned to dead");
    }

    function test_burn_native_eth_to_dead() public {
        vm.deal(address(vault), 5 ether);
        uint256 deadBefore = vault.DEAD().balance;
        vault.burn(address(0));
        assertEq(address(vault).balance, 0, "vault emptied");
        assertEq(vault.DEAD().balance, deadBefore + 5 ether, "eth burned to dead");
    }
}

/// @notice Fork test: pools.trade accepts our BurnVault as the fee recipient of a real launch.
///         Run: forge test --fork-url https://rpc.mainnet.chain.robinhood.com --match-contract BurnVaultForkTest -vvv
contract BurnVaultForkTest is Test {
    address constant LAUNCHER_V3 = 0xE8DCF8898D621C7F40e182eE5Ce9C8715C4F7894;

    function test_fork_launch_with_burn_recipient() public {
        if (LAUNCHER_V3.code.length == 0) { vm.skip(true); return; }
        EverpoolBurnVault vault = new EverpoolBurnVault();
        EverpoolPoolsLauncher ep =
            new EverpoolPoolsLauncher(ILiquidityLauncherV3(LAUNCHER_V3), address(vault));
        address token = ep.launch("Everpool", "POOL");
        assertTrue(token != address(0), "launched with burn vault as fee recipient");
        assertEq(IERC20(token).balanceOf(address(ep)), 0, "supply moved into the pool");
    }
}
