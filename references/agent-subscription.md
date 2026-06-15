# AgentSubscription Operation Instructions

> **Network Configuration**: `<rpc>` is read from `assets/networks.json`.
> Default: Atlantic testnet `https://atlantic.dplabs-internal.com`, chain `688689`.
>
> **Private Key**: pass `--private-key $PRIVATE_KEY` on every write. Always pass
> `--rpc-url <rpc>`. Native token: **PHRS** (18 decimals).

This skill lets an AI agent operate a **recurring pull-payment** system. A
service **provider** (which can be another agent) creates a Plan; a **subscriber**
(or its agent) joins once; then a **keeper/agent** calls `charge` each period to
pull the fee to the provider. The subscriber can `cancel` instantly at any time.

It is the **subscription layer** that complements x402 (per-call) and
AgentSessionWallet (session-key custody).

---

## Core Concepts

| Concept | Meaning |
|---|---|
| **Plan** | `{provider, token, amountPerPeriod, period, active}`. `token=0x0` ⇒ native PHRS. |
| **provider** | Fee recipient + plan owner (can pause/resume). |
| **subscriber** | Who joins a plan. Funds stay under their control until a valid `charge`. |
| **Membership** | One per (subscriber, planId): `nextChargeAt`, `charges`, `cancelledAt`. |
| **charge** | Pull one period's fee if `now >= nextChargeAt`. Anyone may call; funds always go to provider. |
| **Native prefund** | Native-PHRS plans hold wei in-contract; ERC-20 plans pull via `transferFrom` (needs approve). |

---

## Deploy AgentSubscription

**Command Template**
```bash
forge script script/DeployAgentSubscription.s.sol:DeployAgentSubscription \
  --rpc-url <rpc> --private-key $PRIVATE_KEY --broadcast
```
**Output Parsing**: `AgentSubscription address:` → save as `<sub>` for all later
commands. Show `<explorerUrl>/address/<sub>`.

## Verify
```bash
sleep 10
forge verify-contract <sub> src/AgentSubscription.sol:AgentSubscription \
  --chain-id 688689 \
  --verifier-url https://api.socialscan.io/pharos-atlantic-testnet/v1/explorer/command_api/contract \
  --verifier blockscout
```
(No constructor args.)

---

## Create a Plan (provider)

**Command Template**
```bash
cast send <sub> "createPlan(address,uint256,uint64)(uint256)" \
  <token_or_zero> <amountPerPeriod> <period> \
  --private-key $PROVIDER_PRIVATE_KEY --rpc-url <rpc>
```
**Parameters**
| Parameter | Required | Description |
|---|---|---|
| `<token_or_zero>` | Yes | `0x0000...0000` for native PHRS, else ERC-20 address |
| `<amountPerPeriod>` | Yes | Fee per period, smallest unit. ERC20 uses its decimals; native uses wei |
| `<period>` | Yes | Seconds between charges (`86400` daily, `3600` hourly) |

**Output Parsing**: the returned `uint256` is the **planId** (starts at 1). Save it.

**Error Handling**
| Error | Cause | Fix |
|---|---|---|
| `InvalidParams` | amount/period = 0 | Provide non-zero values |

> **Agent Guidelines:** Suggest a USDC (test) plan: token
> `0xE0BE08c77f415F577A1B3A9aD7a1Df1479564ec8`, amount `1000000` (=1 USDC at 6
> decimals), period `86400` (daily). Confirm decimals via `cast call <token> "decimals()(uint8)"`.

---

## Subscribe (ERC-20 plan)

Subscriber must **approve** the contract first, then subscribe.
```bash
# 1. Approve one period (or more)
cast send <token> "approve(address,uint256)" <sub> <amountPerPeriod> \
  --private-key $SUBSCRIBER_PRIVATE_KEY --rpc-url <rpc>

# 2. Subscribe (no value)
cast send <sub> "subscribeERC20(uint256)" <planId> \
  --private-key $SUBSCRIBER_PRIVATE_KEY --rpc-url <rpc>
```
**Error Handling**
| Error | Cause | Fix |
|---|---|---|
| `PlanNotActive` | plan missing or paused | Use a valid, active planId |
| `PlanNotERC20` | plan is native-PHRS | Use `subscribeNative` instead |
| `AlreadySubscribed` | already joined | One membership per plan |

---

## Subscribe (native PHRS plan) + prefund

Prefund N periods in the same call. `msg.value` must equal `amountPerPeriod * N`.
```bash
cast send <sub> "subscribeNative(uint256,uint64)" <planId> <N> \
  --value <amountPerPeriod_times_N> \
  --private-key $SUBSCRIBER_PRIVATE_KEY --rpc-url <rpc>
```
**Error Handling**
| Error | Cause | Fix |
|---|---|---|
| `AmountMismatch` | `msg.value != amount*N` | Send exact wei |
| `PlanNotNative` | plan is ERC-20 | Use `subscribeERC20` |

Top up later: `prefundNative(planId, N)` with matching value.

---

## Charge a period (provider / keeper / agent)

Anyone may call when due. Funds always go to the plan provider.
```bash
cast send <sub> "charge(address,uint256)(uint256)" \
  <subscriber> <planId> \
  --private-key $KEEPER_PRIVATE_KEY --rpc-url <rpc>
```
**Error Handling**
| Error | Cause | Fix |
|---|---|---|
| `NotDueYet(nextChargeAt, now)` | period not elapsed | Wait, or check `secondsUntilDue` first |
| `NotSubscribed` | no membership or cancelled | Subscriber must `subscribe` (or it was `cancel`led) |
| `InsufficientNativePrefund` | native prefund exhausted | Subscriber runs `prefundNative` |
| `TransferFailed` | ERC20 transferFrom failed | Subscriber needs to `approve` enough |

> **Agent Guidelines:** Before charging, read `secondsUntilDue(subscriber, planId)`.
> If it returns `0`, charge. If `-1`, the user is not subscribed. If positive,
> tell the user how long to wait.

---

## Cancel (subscriber kill switch)

Stops future charges immediately. For native plans, refunds remaining prefund.
```bash
cast send <sub> "cancel(uint256)" <planId> \
  --private-key $SUBSCRIBER_PRIVATE_KEY --rpc-url <rpc>
```

---

## Pause / Resume plan (provider)

```bash
cast send <sub> "pausePlan(uint256)" <planId>  --private-key $PROVIDER_PRIVATE_KEY --rpc-url <rpc>
cast send <sub> "resumePlan(uint256)" <planId> --private-key $PROVIDER_PRIVATE_KEY --rpc-url <rpc>
```

---

## Query: status & timing (free — no gas)

### Plan details
```bash
cast call <sub> "getPlan(uint256)(address,address,uint256,uint64,bool)" <planId> --rpc-url <rpc>
# provider, token, amountPerPeriod, period, active
```
### Is subscriber active?
```bash
cast call <sub> "isSubscriberActive(address,uint256)(bool)" <subscriber> <planId> --rpc-url <rpc>
```
### Seconds until next charge (0 = due, -1 = not subscribed)
```bash
cast call <sub> "secondsUntilDue(address,uint256)(int256)" <subscriber> <planId> --rpc-url <rpc>
```
### Membership + native prefund
```bash
cast call <sub> "getMembership(address,uint256)(uint64,uint64,uint64,bool)" <subscriber> <planId> --rpc-url <rpc>
cast call <sub> "nativePrefundOf(address,uint256)(uint256)" <subscriber> <planId> --rpc-url <rpc>
```

---

## Query Events (audit trail)

### Charges collected
```bash
cast logs --rpc-url <rpc> --address <sub> "Charged(address,address,address,uint256,uint64,uint64)"
# topics[1]=subscriber, topics[2]=planId, topics[3]=provider
```
### Subscriptions / cancellations
```bash
cast logs --rpc-url <rpc> --address <sub> "Subscribed(address,uint256,uint64)"
cast logs --rpc-url <rpc> --address <sub> "Cancelled(address,uint256,uint64)"
```

---

## End-to-End Test Sequence
1. **Create plan** (provider) → save `planId`
2. **Subscribe** (subscriber) — approve + subscribeERC20, or subscribeNative{value}
3. **Check** `secondsUntilDue` → equals `period`
4. **Warp** / wait past `period`; `charge` succeeds → provider balance grows
5. **Cancel** (subscriber) → `isSubscriberActive` = false; further `charge` reverts
6. **Query** `Charged` logs → audit trail

## Composability with AgentSessionWallet
An agent's `executeAsAgent` batch can include the `approve` + `subscribeERC20`
calls, so the agent both **approves** and **subscribes** within its session-key
budget. The keeper `charge` can also be called by an agent key. This is how an
autonomous agent subscribes to recurring services entirely on-chain.
