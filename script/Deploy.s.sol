// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/test/shared/HookMiner.sol";

import {EverpoolHook} from "../src/EverpoolHook.sol";
import {EverpoolCompounder} from "../src/EverpoolCompounder.sol";
import {EverpoolLauncher, IEverpoolVault} from "../src/EverpoolLauncher.sol";

/// @notice Deploy the Everpool protocol to Robinhood Chain (testnet first).
/// @dev    Env: POOL_MANAGER (v4 PoolManager on Robinhood Chain), WETH, optional TREASURY,
///         optional PLATFORM_FEE_BPS (default 1000 = 10%).
///         Run: forge script script/Deploy.s.sol --rpc-url robinhood_testnet --broadcast
contract Deploy is Script {
    // CREATE2_FACTORY (0x4e59…4956C) is inherited from forge-std; `new{salt:}` uses it on broadcast.

    function run() external {
        address poolManager = vm.envAddress("POOL_MANAGER");
        address weth = vm.envAddress("WETH");
        address treasury = vm.envOr("TREASURY", msg.sender);
        uint16 platformFeeBps = uint16(vm.envOr("PLATFORM_FEE_BPS", uint256(1000)));

        vm.startBroadcast();

        // 1. Vault / compounder (owns positions, grows pools).
        EverpoolCompounder compounder = new EverpoolCompounder(IPoolManager(poolManager), treasury, platformFeeBps);

        // 2. Hook — mine an address carrying the two liquidity-gating flags, then CREATE2-deploy.
        uint160 flags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG);
        bytes memory args = abi.encode(IPoolManager(poolManager), msg.sender);
        (address hookAddr, bytes32 salt) = HookMiner.find(CREATE2_FACTORY, flags, type(EverpoolHook).creationCode, args);
        EverpoolHook hook = new EverpoolHook{salt: salt}(IPoolManager(poolManager), msg.sender);
        require(address(hook) == hookAddr, "hook address mismatch");

        // 3. Launcher (factory).
        EverpoolLauncher launcher =
            new EverpoolLauncher(IPoolManager(poolManager), IHooks(address(hook)), weth, IEverpoolVault(address(compounder)));

        // 4. Wire: only the vault may add liquidity; the launcher may seed via the vault.
        compounder.setLauncher(address(launcher));
        hook.setAuthorized(address(compounder), true);

        vm.stopBroadcast();

        console2.log("EverpoolHook:      ", address(hook));
        console2.log("EverpoolCompounder:", address(compounder));
        console2.log("EverpoolLauncher:  ", address(launcher));
        console2.log("treasury:          ", treasury);
        console2.log("platformFeeBps:    ", platformFeeBps);
    }
}
