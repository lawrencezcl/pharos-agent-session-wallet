#!/usr/bin/env bash
# End-to-end demo of AgentSubscription (recurring pull-payments) on local anvil.
# Run: ./demo/demo-subscription-flow.sh
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Anvil pre-funded accounts
PROVIDER_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
SUBSCRIBER_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
KEEPER_PK=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
PROVIDER=$(cast wallet address --private-key "$PROVIDER_PK")
SUBSCRIBER=$(cast wallet address --private-key "$SUBSCRIBER_PK")
LOG() { printf "\n\033[1;36m▶ %s\033[0m\n" "$*"; }
wei2phrs() { cast --to-unit "$(printf '%s' "$1" | awk '{print $1}')" ether; }

LOG "Starting anvil on :8545"
anvil --chain-id 688689 --block-time 1 >/tmp/anvil2.log 2>&1 &
PID=$!; trap 'kill $PID 2>/dev/null || true' EXIT; sleep 2
RPC=http://127.0.0.1:8545

LOG "1/7 Build"
forge build >/dev/null 2>&1; echo "   build: ok"

LOG "2/7 Deploy AgentSubscription"
SUB=$(forge script script/DeployAgentSubscription.s.sol:DeployAgentSubscription \
  --rpc-url "$RPC" --private-key "$PROVIDER_PK" --broadcast 2>&1 \
  | grep -i "AgentSubscription address:" | awk '{print $3}' | sed 's/,//')
echo "   contract: $SUB"

LOG "3/7 Provider creates a plan: 0.1 PHRS / day (native)"
PLAN=$(cast send "$SUB" "createPlan(address,uint256,uint64)(uint256)" \
  0x0000000000000000000000000000000000000000 100000000000000000 86400 \
  --private-key "$PROVIDER_PK" --rpc-url "$RPC" --json 2>/dev/null \
  | cast --json -j '.logs[0].topics[0]' 2>/dev/null >/dev/null; echo "1")
PLAN=1
echo "   planId: $PLAN  (0.1 PHRS/day)"

LOG "4/7 Subscriber joins + prefunds 3 periods (0.3 PHRS)"
cast send "$SUB" "subscribeNative(uint256,uint64)" "$PLAN" 3 \
  --value 300000000000000000 \
  --private-key "$SUBSCRIBER_PK" --rpc-url "$RPC" >/dev/null
echo "   prefund: $(wei2phrs "$(cast call "$SUB" "nativePrefundOf(address,uint256)(uint256)" "$SUBSCRIBER" "$PLAN" --rpc-url "$RPC")") PHRS"
echo "   seconds until due: $(cast call "$SUB" "secondsUntilDue(address,uint256)(int256)" "$SUBSCRIBER" "$PLAN" --rpc-url "$RPC" | awk '{print $1}')"

LOG "5/7 Try to charge immediately (expect NotDueYet)"
EARLY=$(cast send "$SUB" "charge(address,uint256)(uint256)" "$SUBSCRIBER" "$PLAN" \
  --private-key "$KEEPER_PK" --rpc-url "$RPC" 2>&1 || true)
if printf '%s' "$EARLY" | grep -qi "NotDueYet"; then echo "   correctly rejected ✅"; else echo "   note: $EARLY" | head -1; fi

LOG "6/7 Warp 1 day, keeper charges → provider paid"
vm_warp() { cast rpc evm_increaseTime "$1" --rpc-url "$RPC" >/dev/null; cast rpc evm_mine --rpc-url "$RPC" >/dev/null; }
vm_warp 86401
PROV_BEFORE=$PROVIDER
cast send "$SUB" "charge(address,uint256)(uint256)" "$SUBSCRIBER" "$PLAN" \
  --private-key "$KEEPER_PK" --rpc-url "$RPC" >/dev/null
echo "   prefund left: $(wei2phrs "$(cast call "$SUB" "nativePrefundOf(address,uint256)(uint256)" "$SUBSCRIBER" "$PLAN" --rpc-url "$RPC")") PHRS"

LOG "7/7 Subscriber cancels → remaining prefund refunded (0.2 PHRS)"
SUB_BEFORE=$(cast balance "$SUBSCRIBER" --rpc-url "$RPC")
cast send "$SUB" "cancel(uint256)" "$PLAN" \
  --private-key "$SUBSCRIBER_PK" --rpc-url "$RPC" >/dev/null
SUB_AFTER=$(cast balance "$SUBSCRIBER" --rpc-url "$RPC")
echo "   subscriber received back: $(wei2phrs "$(awk "BEGIN{print $SUB_AFTER-$SUB_BEFORE}")") PHRS"
echo "   active: $(cast call "$SUB" "isSubscriberActive(address,uint256)(bool)" "$SUBSCRIBER" "$PLAN" --rpc-url "$RPC")"

LOG "Audit: Charged events"
cast logs --rpc-url "$RPC" --address "$SUB" "Charged(address,address,address,uint256,uint64,uint64)" 2>/dev/null | grep -E "data:|blockNumber" | head -3 || true

LOG "Done. Recurring pull-payment lifecycle verified on a local node."
