#!/usr/bin/env bash
# Ships the burn-launchpad code to github.com/0xCookz/everpool-contracts.
# Run this AFTER restoring the Command Line Tools:  xcode-select --install
# (the Mac lost them when it slept, which broke git + gh).
set -euo pipefail
cd "$(dirname "$0")"

git add \
  src/EverpoolBurnVault.sol \
  test/BurnVault.t.sol \
  script/DeployBurn.s.sol \
  keeper/burn-keeper.mjs \
  src/EverpoolPoolsLauncher.sol \
  src/EverpoolToken.sol

git commit -m "feat: burn launchpad — creator fee share burned via pools.trade

EverpoolBurnVault is the fee recipient for every token launched through the
launchpad. pools.trade pushes the creator's ~20% fee share here (launched token
+ native ETH); burn() sweeps it to 0x…dEaD. The other ~80% still autocompounds
into the locked pool. Fork-verified: pools.trade's LiquidityLauncherV3 accepts
the vault as feeRecipient. Adds DeployBurn script + permissionless burn keeper.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"

git push
echo "✅ pushed to everpool-contracts"
