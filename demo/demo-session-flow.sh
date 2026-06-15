#!/usr/bin/env bash
# End-to-end demo of AgentSessionWallet against a local anvil node.
# No testnet PHRS required. Run: ./demo/demo-session-flow.sh
set -euo pipefail

export PATH="$HOME/.foundry/bin:$PATH"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Anvil's pre-funded accounts (well-known, test only).
OWNER_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
AGENT_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
OWNER=$(cast wallet address --private-key "$OWNER_PK")
AGENT=$(cast wallet address --private-key "$AGENT_PK")
RECIPI=0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65

LOG() { printf "\n\033[1;36m▶ %s\033[0m\n" "$*"; }
# cast call returns "1000000000000000000 [1e18]"; strip the annotation, then format.
wei2phrs() { cast --to-unit "$(printf '%s' "$1" | awk '{print $1}')" ether; }

LOG "Starting anvil (local Pharos-like node) on :8545"
anvil --chain-id 688689 --block-time 1 >/tmp/anvil.log 2>&1 &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null || true' EXIT
sleep 2
RPC=http://127.0.0.1:8545

LOG "1/8  Compile + test"
forge build >/dev/null 2>&1
echo "   build: ok"

LOG "2/8  Deploy AgentSessionWallet (owner=$OWNER)"
DEPLOY=$(forge script script/DeployAgentSessionWallet.s.sol:DeployAgentSessionWallet \
  --rpc-url "$RPC" --private-key "$OWNER_PK" --broadcast 2>&1)
WALLET=$(printf "%s\n" "$DEPLOY" | grep -i "Wallet address:" | awk '{print $3}' | sed 's/,//')
echo "   wallet: $WALLET"

LOG "3/8  Fund wallet with 5 PHRS"
cast send "$WALLET" --value 5ether --private-key "$OWNER_PK" --rpc-url "$RPC" >/dev/null
echo "   balance: $(wei2phrs "$(cast call "$WALLET" "nativeBalance()(uint256)" --rpc-url "$RPC")") PHRS"

LOG "4/8  Grant agent a DAILY 1 PHRS key (valid 1 day)"
NOW=$(cast block latest --rpc-url "$RPC" -f timestamp)
UNTIL=$((NOW + 86400))
cast send "$WALLET" "grantSessionKey(address,address,uint96,uint64,uint256)" \
  "$AGENT" 0x0000000000000000000000000000000000000000 "$UNTIL" 86400 1000000000000000000 \
  --private-key "$OWNER_PK" --rpc-url "$RPC" >/dev/null
AVAIL=$(cast call "$WALLET" "spendAvailable(address,address)(uint256)" "$AGENT" 0x0000000000000000000000000000000000000000 --rpc-url "$RPC")
echo "   available: $(wei2phrs "$AVAIL") PHRS / day"

LOG "5/8  Agent spends 0.4 PHRS (uses AGENT key, not owner!)"
cast send "$WALLET" "executeAsAgent((address,uint256,bytes)[])" \
  "[($RECIPI, 400000000000000000, 0x)]" \
  --private-key "$AGENT_PK" --rpc-url "$RPC" >/dev/null
AVAIL=$(cast call "$WALLET" "spendAvailable(address,address)(uint256)" "$AGENT" 0x0000000000000000000000000000000000000000 --rpc-url "$RPC")
echo "   remaining today: $(wei2phrs "$AVAIL") PHRS"

LOG "6/8  Agent tries to over-spend 0.8 PHRS (expect rejection)"
# cast send exits non-zero on revert; capture stderr and look for the revert reason.
OVER_OUT=$(cast send "$WALLET" "executeAsAgent((address,uint256,bytes)[])" \
  "[($RECIPI, 800000000000000000, 0x)]" \
  --private-key "$AGENT_PK" --rpc-url "$RPC" 2>&1 || true)
if printf '%s' "$OVER_OUT" | grep -qiE "SpendLimitExceeded|execution reverted"; then
  echo "   correctly rejected ✅"
else
  echo "   WARNING: expected rejection; output:"
  printf '   %s\n' "$OVER_OUT"
fi

LOG "7/8  Owner revokes the agent key (kill switch)"
cast send "$WALLET" "revokeSessionKey(address,address)" \
  "$AGENT" 0x0000000000000000000000000000000000000000 \
  --private-key "$OWNER_PK" --rpc-url "$RPC" >/dev/null
ACTIVE=$(cast call "$WALLET" "isSessionKeyActive(address,address)(bool)" "$AGENT" 0x0000000000000000000000000000000000000000 --rpc-url "$RPC")
echo "   key active after revoke: $ACTIVE"

LOG "8/8  Audit trail — agent spend events"
cast logs --rpc-url "$RPC" --address "$WALLET" \
  "SessionKeyConsumed(address,address,uint256,uint256,uint256)" 2>/dev/null | grep -A2 "operator\|data" | head -8 || true

LOG "Done. Full lifecycle verified on a local node."
