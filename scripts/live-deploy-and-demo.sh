#!/usr/bin/env bash
# One-shot LIVE deploy + verify + full agent flow on Pharos Atlantic Testnet.
# Prereq: source .env and ensure OWNER has testnet PHRS (faucet).
# Run:  ./scripts/live-deploy-and-demo.sh
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[ -f .env ] && set -a && . ./.env && set +a

: "${PRIVATE_KEY:?set PRIVATE_KEY in .env}"
: "${AGENT_PRIVATE_KEY:?set AGENT_PRIVATE_KEY in .env}"
: "${RPC:=https://atlantic.dplabs-internal.com}"
: "${CHAIN_ID:=688689}"
EXPLORER="https://atlantic.pharosscan.xyz"
VERIFY_URL="https://api.socialscan.io/pharos-atlantic-testnet/v1/explorer/command_api/contract"

OWNER=$(cast wallet address --private-key "$PRIVATE_KEY")
AGENT=$(cast wallet address --private-key "$AGENT_PRIVATE_KEY")
ZERO=0x0000000000000000000000000000000000000000

LOG() { printf "\n\033[1;36m▶ %s\033[0m\n" "$*"; }
wei2phrs() { cast --to-unit "$(printf '%s' "$1" | awk '{print $1}')" ether; }

LOG "Pre-checks"
[ "$(cast chain-id --rpc-url "$RPC")" = "$CHAIN_ID" ] || { echo "wrong chain"; exit 1; }
BAL=$(cast balance "$OWNER" --rpc-url "$RPC" --ether | awk '{print $1}')
echo "owner=$OWNER  agent=$AGENT"
echo "owner balance=$BAL PHRS"
if awk "BEGIN{exit !($BAL < 0.05)}"; then
  echo "❌ Owner needs testnet PHRS. Faucet: https://zan.top/faucet/pharos (send to $OWNER)"
  exit 1
fi

LOG "1/7 Deploy AgentSessionWallet"
DEPLOY=$(forge script script/DeployAgentSessionWallet.s.sol:DeployAgentSessionWallet \
  --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast 2>&1)
WALLET=$(printf "%s\n" "$DEPLOY" | grep -i "Wallet address:" | awk '{print $3}' | sed 's/,//')
echo "wallet: $WALLET"
echo "   explorer: $EXPLORER/address/$WALLET"

LOG "2/7 Verify contract (after 10s indexer delay)"
sleep 10
forge verify-contract "$WALLET" src/AgentSessionWallet.sol:AgentSessionWallet \
  --chain-id "$CHAIN_ID" --verifier-url "$VERIFY_URL" --verifier blockscout \
  --constructor-args "$(cast abi-encode "constructor(address)" "$OWNER")" 2>&1 | tail -3 || \
  echo "   (verification queued; check $EXPLORER/address/$WALLET in ~1 min)"

LOG "3/7 Fund wallet with 0.5 PHRS"
FUNDTX=$(cast send "$WALLET" --value 0.5ether --private-key "$PRIVATE_KEY" --rpc-url "$RPC" --json | cast --json -j .transactionHash 2>/dev/null || echo "?")
echo "   fund tx: $EXPLORER/tx/$FUNDTX"
echo "   wallet balance: $(wei2phrs "$(cast call "$WALLET" "nativeBalance()(uint256)" --rpc-url "$RPC")") PHRS"

LOG "4/7 Grant agent a DAILY 0.3 PHRS key (valid 1 day)"
NOW=$(cast block latest --rpc-url "$RPC" -f timestamp)
UNTIL=$((NOW + 86400))
GRANTTX=$(cast send "$WALLET" "grantSessionKey(address,address,uint96,uint64,uint256)" \
  "$AGENT" "$ZERO" "$UNTIL" 86400 300000000000000000 \
  --private-key "$PRIVATE_KEY" --rpc-url "$RPC" --json | cast --json -j .transactionHash 2>/dev/null || echo "?")
echo "   grant tx: $EXPLORER/tx/$GRANTTX"
echo "   available: $(wei2phrs "$(cast call "$WALLET" "spendAvailable(address,address)(uint256)" "$AGENT" "$ZERO" --rpc-url "$RPC")") PHRS/day"

LOG "5/7 Agent spends 0.1 PHRS (AGENT key, not owner!)"
# send change back to owner so funds aren't lost
SPENDTX=$(cast send "$WALLET" "executeAsAgent((address,uint256,bytes)[])" \
  "[(\"$OWNER\", 100000000000000000, 0x)]" \
  --private-key "$AGENT_PRIVATE_KEY" --rpc-url "$RPC" --json | cast --json -j .transactionHash 2>/dev/null || echo "?")
echo "   spend tx: $EXPLORER/tx/$SPENDTX"
echo "   remaining today: $(wei2phrs "$(cast call "$WALLET" "spendAvailable(address,address)(uint256)" "$AGENT" "$ZERO" --rpc-url "$RPC")") PHRS"

LOG "6/7 Owner revokes the agent key (kill switch)"
REVOKETX=$(cast send "$WALLET" "revokeSessionKey(address,address)" "$AGENT" "$ZERO" \
  --private-key "$PRIVATE_KEY" --rpc-url "$RPC" --json | cast --json -j .transactionHash 2>/dev/null || echo "?")
echo "   revoke tx: $EXPLORER/tx/$REVOKETX"
echo "   key active: $(cast call "$WALLET" "isSessionKeyActive(address,address)(bool)" "$AGENT" "$ZERO" --rpc-url "$RPC")"

LOG "7/7 Audit trail (agent spend events on-chain)"
cast logs --rpc-url "$RPC" --address "$WALLET" \
  "SessionKeyConsumed(address,address,uint256,uint256,uint256)" 2>/dev/null | grep -E "data:|blockNumber:" | head -4 || true

LOG "✅ DONE. Add these to BUIDL.md / DoraHacks:"
echo "   Wallet: $EXPLORER/address/$WALLET"
echo "   Grant:  $EXPLORER/tx/$GRANTTX"
echo "   Spend:  $EXPLORER/tx/$SPENDTX"
echo "   Revoke: $EXPLORER/tx/$REVOKETX"

# ────────────────────────────────────────────────────────────────────
# Module 2: AgentSubscription (recurring pull-payments)
# ────────────────────────────────────────────────────────────────────
LOG "Module 2 — Deploy AgentSubscription"
SUBADDR=$(forge script script/DeployAgentSubscription.s.sol:DeployAgentSubscription \
  --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast 2>&1 \
  | grep -i "AgentSubscription address:" | awk '{print $3}' | sed 's/,//')
echo "   subscription: $SUBADDR"
echo "   explorer: $EXPLORER/address/$SUBADDR"

LOG "Module 2 — Verify subscription contract"
sleep 10
forge verify-contract "$SUBADDR" src/AgentSubscription.sol:AgentSubscription \
  --chain-id "$CHAIN_ID" --verifier-url "$VERIFY_URL" --verifier blockscout 2>&1 | tail -2 || true

LOG "Module 2 — Create a 0.01 PHRS/hour plan (provider = owner)"
PLAN_TX=$(cast send "$SUBADDR" "createPlan(address,uint256,uint64)(uint256)" \
  "$ZERO" 10000000000000000 3600 \
  --private-key "$PRIVATE_KEY" --rpc-url "$RPC" --json | cast --json -j .transactionHash 2>/dev/null || echo "?")
echo "   createPlan tx: $EXPLORER/tx/$PLAN_TX"

LOG "Module 2 — Subscriber (agent key) joins + prefunds 2 hours (0.02 PHRS)"
SUB_TX=$(cast send "$SUBADDR" "subscribeNative(uint256,uint64)" 1 2 \
  --value 20000000000000000 \
  --private-key "$AGENT_PRIVATE_KEY" --rpc-url "$RPC" --json | cast --json -j .transactionHash 2>/dev/null || echo "?")
echo "   subscribe tx: $EXPLORER/tx/$SUB_TX"
echo "   seconds until due: $(cast call "$SUBADDR" "secondsUntilDue(address,uint256)(int256)" "$AGENT" 1 --rpc-url "$RPC" | awk '{print $1}')"

LOG "Module 2 — Subscriber cancels → prefund refunded"
CANCEL_TX=$(cast send "$SUBADDR" "cancel(uint256)" 1 \
  --private-key "$AGENT_PRIVATE_KEY" --rpc-url "$RPC" --json | cast --json -j .transactionHash 2>/dev/null || echo "?")
echo "   cancel tx: $EXPLORER/tx/$CANCEL_TX"

echo
echo "=========================================================="
echo "✅ ALL DONE — both skills deployed. Add to BUIDL.md:"
echo "   AgentSessionWallet: $EXPLORER/address/$WALLET"
echo "   AgentSubscription:  $EXPLORER/address/$SUBADDR"
echo "=========================================================="
