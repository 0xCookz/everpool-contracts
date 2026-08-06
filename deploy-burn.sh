#!/usr/bin/env bash
# Deploy del burn launchpad a Robinhood Chain MAINNET.
# Tu clave privada se guarda CIFRADA en tu Mac (~/.foundry/keystores/deployer).
# Nadie más la ve — ni siquiera se escribe en pantalla. Firmas con una contraseña que tú eliges.
set -euo pipefail

FB="$HOME/.foundry/bin"
RPC="https://rpc.mainnet.chain.robinhood.com"
DIR="/Users/diego_carsten/Desktop/Claude/pools-launchpad/contracts"
cd "$DIR"

echo "════════════════════════════════════════════════════════"
echo "  Everpool · deploy burn launchpad → Robinhood mainnet"
echo "════════════════════════════════════════════════════════"

# 1) Cofre cifrado con tu clave (solo la primera vez)
if [ ! -f "$HOME/.foundry/keystores/deployer" ]; then
  echo
  echo ">> PASO 1: pega tu CLAVE PRIVADA y elige una CONTRASEÑA."
  echo "   (se guarda cifrada en tu Mac; no aparece en pantalla ni en logs)"
  echo
  "$FB/cast" wallet import deployer --interactive
fi

# 2) Dirección + saldo (te pedirá la contraseña del cofre)
echo
echo ">> PASO 2: comprobando tu wallet…"
ADDR=$("$FB/cast" wallet address --account deployer)
BAL=$("$FB/cast" balance "$ADDR" --rpc-url "$RPC" --ether)
echo "   Deployer: $ADDR"
echo "   Saldo:    $BAL ETH   (gas del deploy ≈ céntimos)"

# 3) Deploy (te pedirá la contraseña otra vez para firmar)
echo
echo ">> PASO 3: deployando BurnVault + PoolsLauncher…"
"$FB/forge" script script/DeployBurn.s.sol \
  --rpc-url "$RPC" \
  --account deployer --sender "$ADDR" \
  --broadcast

echo
echo "✅ LISTO. Vuelve al chat y escribe 'hecho' — yo leo las direcciones"
echo "   desplegadas y las conecto a la web automáticamente."
