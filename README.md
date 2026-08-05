# Everpool — contracts

On-chain launchpad for **Everpool**: launch a token whose trading fees are permanently folded back
into its own Uniswap **v4** pool on **Robinhood Chain**. See [ARCHITECTURE.md](ARCHITECTURE.md).

> ⚠️ **Prototype, not audited.** Testnet only until tested end-to-end and professionally audited.

## Contracts (`src/`)
- `EverpoolToken.sol` — fixed-supply ERC20, minted once to the launcher.
- `EverpoolHook.sol` — v4 hook: liquidity is protocol-owned and **permanent** (add = protocol-only,
  remove = never).
- `EverpoolLauncher.sol` — factory: deploy token → init v4 pool → seed & lock liquidity → register.
- `EverpoolCompounder.sol` — collects accrued fees and re-adds them as liquidity (the "grow" engine),
  callable every ~10 min by a keeper or anyone.

## Setup
```bash
# 1) Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# 2) macOS only: forge needs libusb. With Homebrew:
brew install libusb
# …or without Homebrew, point DYLD_FALLBACK_LIBRARY_PATH at a libusb-1.0.0.dylib.

# 3) deps
forge install foundry-rs/forge-std Uniswap/v4-core Uniswap/v4-periphery OpenZeppelin/openzeppelin-contracts

# 4) build & test
forge build
forge test -vvv
```

## Deploy (testnet first)
```bash
forge script script/Deploy.s.sol --rpc-url robinhood_testnet --broadcast
```
Requires the Robinhood-Chain Uniswap v4 `PoolManager` address and the pair asset (WETH/USDG) — set in
`.env` / the script. Chain IDs: mainnet `4663`, testnet `46630`.

## Keeper
`keeper/` runs the 10-minute compound loop (`compound(poolId)`) across registered pools.
