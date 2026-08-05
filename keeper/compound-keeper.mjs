// Everpool compound keeper — calls compound(poolId) on a fixed cadence for each registered pool.
// The pool only grows: fees accrue, this folds them back into the locked liquidity.
//
// Usage:  node compound-keeper.mjs
// Env (.env):  RPC_URL, PRIVATE_KEY, COMPOUNDER, POOL_IDS (comma-separated bytes32), INTERVAL_MS
//
// Note: compound() is permissionless — the keeper is just a reliable caller. Anyone can run this,
// and the contract can pay the caller a small keeper incentive (see EverpoolCompounder).

import { ethers } from "ethers";

const RPC_URL = process.env.RPC_URL ?? "https://rpc.testnet.chain.robinhood.com";
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const COMPOUNDER = process.env.COMPOUNDER;
const POOL_IDS = (process.env.POOL_IDS ?? "").split(",").map((s) => s.trim()).filter(Boolean);
const INTERVAL_MS = Number(process.env.INTERVAL_MS ?? 10 * 60 * 1000); // 10 minutes

const ABI = ["function compound(bytes32 poolId) external returns (uint256 added)"];

if (!PRIVATE_KEY || !COMPOUNDER || POOL_IDS.length === 0) {
  console.error("Missing env: PRIVATE_KEY, COMPOUNDER and POOL_IDS are required.");
  process.exit(1);
}

const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
const compounder = new ethers.Contract(COMPOUNDER, ABI, wallet);

async function cycle() {
  for (const poolId of POOL_IDS) {
    try {
      const tx = await compounder.compound(poolId);
      console.log(`[${new Date().toISOString()}] compound(${poolId.slice(0, 10)}…) sent: ${tx.hash}`);
      const rc = await tx.wait();
      console.log(`  mined in block ${rc.blockNumber} (gas ${rc.gasUsed})`);
    } catch (e) {
      console.error(`  compound(${poolId.slice(0, 10)}…) failed:`, e.shortMessage ?? e.message);
    }
  }
}

console.log(`Everpool keeper: ${POOL_IDS.length} pool(s), every ${INTERVAL_MS / 1000}s, from ${wallet.address}`);
await cycle();
setInterval(cycle, INTERVAL_MS);
