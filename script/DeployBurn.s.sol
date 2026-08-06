// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {EverpoolBurnVault} from "../src/EverpoolBurnVault.sol";
import {EverpoolPoolsLauncher, ILiquidityLauncherV3} from "../src/EverpoolPoolsLauncher.sol";

/// @notice Deploy the burn launchpad on Robinhood Chain MAINNET (pools.trade's launcher is mainnet-only).
/// @dev    Run: forge script script/DeployBurn.s.sol --rpc-url https://rpc.mainnet.chain.robinhood.com --account deployer --broadcast
contract DeployBurn is Script {
    // pools.trade LiquidityLauncherV3 on Robinhood Chain mainnet
    address constant LAUNCHER_V3 = 0xE8DCF8898D621C7F40e182eE5Ce9C8715C4F7894;

    function run() external {
        vm.startBroadcast();

        // fee recipient that burns the creator's fee share
        EverpoolBurnVault vault = new EverpoolBurnVault();

        // launcher: every token launched through it burns its creator fees
        EverpoolPoolsLauncher launcher =
            new EverpoolPoolsLauncher(ILiquidityLauncherV3(LAUNCHER_V3), address(vault));

        vm.stopBroadcast();

        console2.log("EverpoolBurnVault:     ", address(vault));
        console2.log("EverpoolPoolsLauncher: ", address(launcher));
        console2.log("-> paste the launcher address into the website's CONTRACTS.launcher");
    }
}
