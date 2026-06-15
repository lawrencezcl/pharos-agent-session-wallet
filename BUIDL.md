# BUIDL Submission — AgentSessionWallet

> **Copy-paste ready content for the DoraHacks submission form.**
> Repo: https://github.com/lawrencezcl/pharos-agent-session-wallet

---

## Title

Pharos Agent Economy Toolkit — Session-Key Custody + Recurring Subscriptions

## Tagline (one-liner)

Two foundational on-chain primitives for AI agents: a session-key wallet (scoped
autonomy, zero key exposure) and a recurring pull-payment subscription system.

## Description

This **Pharos Skill** package delivers two foundational primitives of the
on-chain AI-agent economy. An agent that transacts on-chain should never hold a
user's real private key, and needs a way to pay for recurring services — these
two modules solve exactly that.

### Module 1 — AgentSessionWallet (custody)
A smart-contract wallet that grants an AI agent a **session key**: a separate,
throwaway key that can only spend what the owner allows — a hard time expiry, a
per-token spending cap over a rolling window, and an instant kill switch. The
session-key pattern (behind Coinbase Smart Wallet / Alchemy Account Kit), now
native to Pharos.

### Module 2 — AgentSubscription (recurring payments)
A pull-payment primitive where a provider (which may itself be an agent) creates
a Plan (token, amountPerPeriod, period); a subscriber joins once; then a
keeper/agent calls `charge` each period to pull the fee. The subscriber can
cancel instantly. This is the **subscription layer** that complements x402
(per-call) — the one thing agents need for recurring service payments.

### What it does
- **Wallet**: deploy → fund → grant a time-boxed, capped session key (native or
  ERC-20) → agent spends autonomously within budget → instant revoke → audit trail
- **Subscription**: create plan → subscribe (ERC20 approve or native prefund) →
  keeper charges each period → cancel anytime with refund → audit trail
- **Composable**: an agent's `executeAsAgent` batch can approve + subscribe in
  one call, all within its session-key budget. Wallet can call any contract,
  composing with x402, airdrop, vault, DEX skills.

### Why it's the foundational Phase-1 skill
Every Phase-2 agent that spends, trades, or pays on Pharos first needs a wallet
it can safely control. AgentSessionWallet is that primitive — and it's
delivered as a standard, reusable Pharos Skill (SKILL.md + reference manual +
contract template) that any agent can call via natural language.

### How an agent uses it (natural language → on-chain)
```
"Deploy an agent wallet and grant my bot 0.5 PHRS/day for 24 hours"
→ agent reads SKILL.md → Capability Index → references/agent-wallet.md
→ runs forge/cast → wallet deployed, key granted
→ bot now spends autonomously, capped at 0.5 PHRS/day, expiring in 24h
```

## How we built it
- **Solidity ^0.8.24** — `AgentSessionWallet.sol` (batching, rolling-window spend
  limits, per-token grants, instant revoke) and `AgentSubscription.sol` (plans,
  ERC20/native pull-payment, prefund accounting, keeper `charge`)
- **Foundry** (forge/cast) as the Skill Engine runtime — the standard Pharos way
- **Skill package**: `SKILL.md` (frontmatter + dual Capability Index) +
  `references/agent-wallet.md` + `references/agent-subscription.md` +
  `assets/{networks,tokens}.json`
- **33 Foundry unit tests, all passing** (17 wallet + 16 subscription)
- **Local end-to-end demos** verified on `anvil` at chain ID 688689 (both modules)

## Challenges / technical highlights
- Enforcing both **native value** (`Call.value`) and **ERC-20** spend in a single
  batch by detecting the `transfer(address,uint256)` selector (`0xa9059cbb`)
- Correct **rolling-window** accounting that resets spend when the period elapses
  while preserving an open window's budget on re-grant
- Gas-aware storage packing (`uint96`/`uint64`) and human-readable custom errors
  so the agent can parse reverts for the user

## Demo
- **Code**: https://github.com/lawrencezcl/pharos-agent-session-wallet
- **Local lifecycle demos** (no testnet tokens needed):
  - Wallet: `./demo/demo-session-flow.sh` — deploy→fund→grant→spend→overspend-rejected→revoke→audit
  - Subscription: `./demo/demo-subscription-flow.sh` — createPlan→prefund→early-charge-rejected→charge→cancel-refund
- **Live testnet**: both contracts deployed & verified on Pharos Atlantic Testnet
  (chain 688689). [Paste explorer addresses after `./scripts/live-deploy-and-demo.sh`]

## Tech stack
Solidity · Foundry (forge/cast) · Pharos Skill Engine · Pharos Atlantic Testnet ·
EVM-compatible (viem/ethers ready) · AI-agent-driven (Claude Code / Codex)

## What's next
- Compose into a full Phase-2 agent (wallet + subscription + x402 agent-commerce + DEX skills)
- Add ERC-4337 EntryPoint integration for gasless/paymaster-sponsored sessions
- Permit2 support for gasless approvals from agent sessions

## Alignment with Pharos vision
Pharos is built for the **AI Agent Economy**. Delegated, scoped on-chain
autonomy is the core capability that economy requires — and safe custody is its
prerequisite. AgentSessionWallet makes "an agent that can pay, trade and
transact on Pharos without ever touching your keys" a one-prompt reality.

---

### Judging criteria → how we deliver
| Criterion | Delivery |
|---|---|
| Originality | First session-key custody Skill for Pharos; not a built-in (ERC20/airdrop/vault) |
| Technical quality | 17 unit tests, reentrancy-safe batching, packed storage, custom errors |
| Practical use case | The custody primitive every spending agent needs |
| Reusability/composability | Wallet calls any contract; composes with x402, airdrop, vault, DEX |
| Pharos deployment | Compiles & verifies on Atlantic testnet via Foundry |
| Docs/UX | Natural-language driven; SKILL.md + reference + demo |
| Agent-economy alignment | Enables delegated on-chain autonomy — Pharos's stated vision |
