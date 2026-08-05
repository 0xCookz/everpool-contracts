# Everpool Protocol — Architecture

> **Status: prototype / testnet-first.** This code is under active construction and has **not** been
> audited. Do not deploy to mainnet with real funds until it is tested end-to-end and professionally
> audited. Smart-contract bugs are irreversible and lose money.

## The idea (one sentence)
Launch a token whose **trading fees are permanently folded back into its own liquidity pool** — so the
pool only ever gets bigger, and nobody (not even the creator) can pull the liquidity out.

## Target chain & DEX
- **Robinhood Chain** (EVM). Mainnet `chainId 4663` — RPC `https://rpc.mainnet.chain.robinhood.com`.
  Testnet `chainId 46630` — RPC `https://rpc.testnet.chain.robinhood.com`. Native asset: ETH.
- **Uniswap v4** is deployed on Robinhood Chain (v2/v3/v4 all live). We build on **v4 + hooks** — this
  is what "on pools.trade" means at the protocol level (Uniswap v4 on Robinhood Chain).
- Deploy tooling: **Foundry** (Robinhood documents this).

## Why Uniswap v4 hooks
A v4 *hook* is a contract attached to a pool that runs custom logic on swaps / liquidity changes. That
is exactly the primitive we need to (a) **lock** liquidity forever and (b) route/track fees so they can
be **compounded back into the pool**.

## Components

### 1. `EverpoolToken` (ERC20)
Fixed supply, minted once to the Launcher at creation. No further minting. This is the launched token.

### 2. `EverpoolHook` (Uniswap v4 hook)
Attached to every Everpool pool. Hook permissions & jobs:
- `beforeAddLiquidity` — **allow-list**: only the protocol (Launcher / Compounder) may add liquidity.
  Regular users trade; they don't LP. This keeps the pool's liquidity protocol-owned.
- `beforeRemoveLiquidity` — **revert always**: liquidity is permanent. It can only grow.
- `afterSwap` *(optional)* — platform-fee split (the flywheel): route a configurable % of the swap fee
  to the Everpool treasury / protocol pool; the rest stays in the token's own pool. Default configurable.
- Accounting of accrued fees per pool for the Compounder.

### 3. `EverpoolLauncher` (factory) — the launch flow, one transaction
1. Deploy `EverpoolToken` (fixed supply).
2. Initialize a v4 pool: `token / <PAIR_ASSET>` with `EverpoolHook`, at an initial price.
3. Seed a **full-range** liquidity position, **owned & locked** by the protocol.
4. Register the pool for compounding.
5. `emit Launched(token, poolId, creator)`.

### 4. `EverpoolCompounder` — `compound(poolId)`
The engine that "grows the pool", designed to run every ~10 minutes:
1. Collect accrued fees (token0 + token1) from the locked position (v4: `modifyLiquidity(0)` settles fees).
2. Balance the two sides to the current pool ratio (swap the surplus side — the "swap-half" analog).
3. Add the balanced amount as liquidity to the locked position → **pool depth increases**.
4. Callable by **anyone**; pays the caller a tiny bps keeper-incentive so a bot (or the public) keeps it
   ticking. We also ship an off-chain keeper that calls it on a 10-min cadence per pool.

## Flywheel (loop)
bigger pool → tighter prices → more volume → more fees → compounded back → bigger pool. Forever.

## Security surface (to handle before mainnet)
- v4 `PoolManager` unlock/callback reentrancy discipline.
- Compound-time swap: bound slippage / use a spot-vs-TWAP check to resist sandwiching the compound tx.
- Hook address must encode the correct permission flags (v4 mines the hook address).
- Access control on Launcher/Compounder; no admin path to drain the locked LP.
- Fee-on-transfer / rebasing pair assets excluded.
- Full test suite + fork tests on Robinhood testnet + audit.

## Open decisions (need your call — defaults chosen so we can build now)
1. **Pair asset**: default **WETH**. Alt: **USDG** (Robinhood stablecoin) or native ETH.
2. **Fee split**: default **100% back into the token's own pool** (purest). Alt: carve **10%** into an
   Everpool protocol pool/token (value-capture flywheel, like Liquidify).
3. **Compound cadence/trigger**: default **public `compound()` + keeper every 10 min**.
4. **Launch economics**: is there a **launch fee** the creator pays? default **0** for now.
5. **Token defaults**: supply `1_000_000_000e18`, initial price / initial liquidity — TBD.

## Build order
`EverpoolToken` → `EverpoolHook` → `EverpoolLauncher` → `EverpoolCompounder` → tests (unit + fork) →
deploy scripts → keeper bot → testnet dry-run → audit → mainnet.
