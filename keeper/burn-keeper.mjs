// Everpool burn keeper — burns the creator fees accrued in the BurnVault for EVERY launched token.
//
// Auto-discovers all tokens from the launcher's `Launched` events (no manual list needed), then for
// each one — plus the shared native-ETH fees — calls the permissionless `burn()` on the vault.
//
// Modes:
//   RUN_ONCE=true  (default) -> run one cycle and exit. Use with a cron / GitHub Actions schedule.
//   RUN_ONCE=false           -> loop forever every INTERVAL_MS. Use on an always-on server.
//
// Env:  PRIVATE_KEY (required, a funded gas wallet — burn is permissionless so any key works),
//       RPC_URL, LAUNCHER, BURN_VAULT, INTERVAL_MS, RUN_ONCE

import { ethers } from "ethers";

const RPC_URL     = process.env.RPC_URL     ?? "https://rpc.mainnet.chain.robinhood.com";
const LAUNCHER    = process.env.LAUNCHER    ?? "0xb2e716736ae4af757c0b24aae7b2bd26dc910b08";
const BURN_VAULT  = process.env.BURN_VAULT  ?? "0x39a750af34db27d8611b2836a31d301dfe366bfa";
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const INTERVAL_MS = Number(process.env.INTERVAL_MS ?? 15 * 60 * 1000);
const RUN_ONCE    = (process.env.RUN_ONCE ?? "true").toLowerCase() !== "false";
const NATIVE      = "0x0000000000000000000000000000000000000000";
// keccak256("Launched(address,address,string,string)")
const LAUNCHED_TOPIC = "0xa6f2b8981631a2b06092746b2d22a69bb8887f2dd9b28af5282d0d2bf87601a2";

if (!PRIVATE_KEY) { console.error("Missing env: PRIVATE_KEY is required."); process.exit(1); }

const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet   = new ethers.Wallet(PRIVATE_KEY, provider);
const vault    = new ethers.Contract(BURN_VAULT, ["function burn(address currency) external returns (uint256)"], wallet);

async function discoverTokens() {
  const logs = await provider.getLogs({ address: LAUNCHER, topics: [LAUNCHED_TOPIC], fromBlock: 0, toBlock: "latest" });
  return [...new Set(logs.map((l) => ethers.getAddress("0x" + l.topics[1].slice(26))))];
}

async function burn(currency, label) {
  try {
    const tx = await vault.burn(currency);
    const rc = await tx.wait();
    console.log(`[${new Date().toISOString()}] burn(${label}) -> ${tx.hash}  (block ${rc.blockNumber})`);
  } catch (e) {
    console.error(`  burn(${label}) failed:`, e.shortMessage ?? e.message);
  }
}

async function cycle() {
  const tokens = await discoverTokens();
  console.log(`vault ${BURN_VAULT} — ${tokens.length} token(s) discovered`);
  await burn(NATIVE, "ETH");
  for (const t of tokens) await burn(t, t.slice(0, 10) + "…");
}

await cycle();
if (!RUN_ONCE) setInterval(cycle, INTERVAL_MS);
