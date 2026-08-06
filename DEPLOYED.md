# Everpool burn launchpad — deployed addresses

**Network:** Robinhood Chain mainnet (chainId 4663 / 0x1237)
**Deployed:** 2026-08-06, via MetaMask (account 0xA83Bfac23322ee7CdfAd6Ac7851c3B951D3D1066)

| Contract | Address |
|---|---|
| **EverpoolPoolsLauncher** | `0xb2e716736ae4af757c0b24aae7b2bd26dc910b08` |
| **EverpoolBurnVault** | `0x39a750af34db27d8611b2836a31d301dfe366bfa` |
| pools.trade LiquidityLauncherV3 (external) | `0xE8DCF8898D621C7F40e182eE5Ce9C8715C4F7894` |

**On-chain verification (cast):**
- `EverpoolPoolsLauncher.launcher()` → `0xE8DCF8898D621C7F40e182eE5Ce9C8715C4F7894` (pools.trade) ✓
- `EverpoolPoolsLauncher.feeRecipient()` → `0x39a750…366bfa` (BurnVault) ✓
- `EverpoolBurnVault.DEAD()` → `0x…dEaD` ✓

Every token launched through `EverpoolPoolsLauncher.launch(name, symbol)` is a genuine pools.trade
token; ~80% of its trading fees autocompound into the permanently-locked pool, and the creator's
~20% share is routed to the BurnVault and burned (permissionless `burn(currency)`), so no dev ever
takes a cut.

The website's `CONTRACTS.launcher` points at the PoolsLauncher above.
