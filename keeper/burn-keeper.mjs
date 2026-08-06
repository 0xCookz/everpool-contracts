// Everpool burn keeper — periodically burns the creator fees that have accrued in the BurnVault.
// For every launched token it sends that token's accrued fees (and the shared native-ETH fees) to
// the dead address. Permissionless: anyone can run this.
//
// Usage:  node burn-keeper.mjs
// Env (.env):  RPC_URL, PRIVATE_KEY, BURN_VAULT, TOKENS (comma-separated token addresses), INTERVAL_MS

import { ethers } from "ethers";

const RPC_URL = process.env.RPC_URL ?? "https://rpc.mainnet.chain.robinhood.com";
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const BURN_VAULT = process.env.BURN_VAULT;
const TOKENS = (process.env.TOKENS ?? "").split(",").map((s) => s.trim()).filter(Boolean);
const INTERVAL_MS = Number(process.env.INTERVAL_MS ?? 15 * 60 * 1000); // 15 minutes
const NATIVE = "0x0000000000000000000000000000000000000000";

const ABI = ["function burn(address currency) external returns (uint256 amount)"];

if (!PRIVATE_KEY || !BURN_VAULT) {
  console.error("Missing env: PRIVATE_KEY and BURN_VAULT are required.");
  process.exit(1);
}

const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
const vault = new ethers.Contract(BURN_VAULT, ABI, wallet);

async function burn(currency, label) {
  try {
    const tx = await vault.burn(currency);
    console.log(`[${new Date().toISOString()}] burn(${label}) -> ${tx.hash}`);
    const rc = await tx.wait();
    console.log(`  mined block ${rc.blockNumber} (gas ${rc.gasUsed})`);
  } catch (e) {
    console.error(`  burn(${label}) failed:`, e.shortMessage ?? e.message);
  }
}

async function cycle() {
  await burn(NATIVE, "ETH"); // shared native-ETH fees across all pools
  for (const t of TOKENS) await burn(t, t.slice(0, 10) + "…");
}

console.log(`Everpool burn keeper: vault ${BURN_VAULT}, ${TOKENS.length} token(s), every ${INTERVAL_MS / 1000}s`);
await cycle();
setInterval(cycle, INTERVAL_MS);
