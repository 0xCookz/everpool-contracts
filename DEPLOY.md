# Deploy runbook

> Verified: the script deploys cleanly against a **fork of Robinhood Chain mainnet** (real Uniswap v4),
> using anvil's pre-funded test account. For a real broadcast you only swap the RPC + a funded key.
> **Do testnet first. Audit before mainnet with real money.** The deployer wallet becomes the
> protocol **owner/admin** (sets treasury + fee %, wires contracts) — but it can NEVER remove the
> locked liquidity; that's fixed in the hook.

## 0. What you need
- A **dedicated deployer wallet** (not your main), with a little ETH for gas.
- Its private key, kept **only on your machine** (never shared, never committed).

## 1. Local dry-run against a fork (free, no key of yours)
```bash
# terminal A: fork Robinhood mainnet locally
anvil --fork-url https://rpc.mainnet.chain.robinhood.com

# terminal B: deploy to the fork with anvil's test account
export POOL_MANAGER=0x8366a39CC670B4001A1121B8F6A443A643e40951
export WETH=0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

## 2. Real broadcast (your funded wallet)
Store the key safely as an encrypted keystore instead of plain text:
```bash
cast wallet import deployer --interactive   # paste your key ONCE; it's encrypted on disk
```
Then:
```bash
export POOL_MANAGER=0x8366a39CC670B4001A1121B8F6A443A643e40951   # (mainnet v4 PoolManager)
export WETH=0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73
# export TREASURY=0xYourTreasury      # optional; defaults to deployer
forge script script/Deploy.s.sol --rpc-url https://rpc.mainnet.chain.robinhood.com \
  --account deployer --broadcast --verify
```
> Testnet target (chainId 46630) is preferred first, but its Uniswap v4 PoolManager address is not
> published yet — needs confirming before a testnet run.

## 3. After deploy
- `EverpoolLauncher.launch(name, symbol, wethSeed)` creates a token + locked pool (needs WETH approved).
- Run the keeper (`keeper/compound-keeper.mjs`) with `COMPOUNDER` + the pool ids to grow pools every 10 min.
- Consider transferring `owner` of the hook + compounder to a **multisig**.
