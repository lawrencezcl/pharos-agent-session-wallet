# BUIDL Submission — AgentSessionWallet

> **Copy-paste ready content for the DoraHacks submission form.**
> Repo: https://github.com/lawrencezcl/pharos-agent-session-wallet

---

## Title

AgentSessionWallet — Session-Key Custody for On-Chain AI Agents

## Tagline (one-liner)

Give an AI agent a time-boxed, spending-capped wallet key — full agent autonomy on Pharos, zero private-key exposure.

## Description

AgentSessionWallet is a **Pharos Skill** that gives any AI agent a **custody
primitive**: a smart-contract wallet that issues **session keys** to agents.

An AI agent that transacts on-chain should never hold a user's real private key.
AgentSessionWallet solves this with the session-key pattern (the same idea behind
Coinbase Smart Wallet and Alchemy Account Kit, now native to Pharos): the human
**owner** deposits funds and grants the agent a separate, throwaway key that can
only spend **what the owner allows** — a hard time expiry, a per-token spending
cap over a rolling window, and an instant kill switch.

### What it does
- **Deploy** a smart-contract wallet owned by the human
- **Grant a session key**: pick the agent's address, an expiry (e.g. +1 day), a
  rolling window (e.g. daily), and a spend limit (e.g. 1 PHRS/day) — per token
  (native PHRS or any ERC-20, e.g. USDC for agent commerce)
- **Agent acts**: calls `executeAsAgent` to transfer PHRS/tokens or call any
  contract, fully autonomously, within budget
- **Enforced on-chain**: overspend reverts; the budget resets each window
- **Revoke instantly**: owner cancels a key in one transaction
- **Full audit trail**: every action emits events queryable with `cast logs`
- **Composable**: the wallet can call **any** contract, so it composes with the
  x402, airdrop, vault and DEX skills into complete Phase-2 agents

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
- **Solidity ^0.8.24** smart contract (`AgentSessionWallet.sol`): batching,
  per-(operator,token) grants, rolling-window spend math, reentrancy-safe
- **Foundry** (forge/cast) as the Skill Engine runtime — the standard Pharos way
- **Skill package**: `SKILL.md` (frontmatter + Capability Index, 12 intents) +
  `references/agent-wallet.md` (357-line machine-readable ops manual) +
  `assets/{networks,tokens}.json`
- **17 Foundry unit tests, all passing**
- **Local end-to-end demo** verified on an `anvil` node at chain ID 688689

## Challenges / technical highlights
- Enforcing both **native value** (`Call.value`) and **ERC-20** spend in a single
  batch by detecting the `transfer(address,uint256)` selector (`0xa9059cbb`)
- Correct **rolling-window** accounting that resets spend when the period elapses
  while preserving an open window's budget on re-grant
- Gas-aware storage packing (`uint96`/`uint64`) and human-readable custom errors
  so the agent can parse reverts for the user

## Demo
- **Code**: https://github.com/lawrencezcl/pharos-agent-session-wallet
- **Local lifecycle demo**: `./demo/demo-session-flow.sh` — runs
  deploy → fund → grant → agent-spend → overspend-rejected → revoke → audit log
  on a local node (no testnet tokens needed). Full output in the repo README.
- **Live testnet**: contract deployed & verified on Pharos Atlantic Testnet
  (chain 688689). [Paste explorer address after `./scripts/live-deploy-and-demo.sh`]

## Tech stack
Solidity · Foundry (forge/cast) · Pharos Skill Engine · Pharos Atlantic Testnet ·
EVM-compatible (viem/ethers ready) · AI-agent-driven (Claude Code / Codex)

## What's next
- Compose into a full Phase-2 agent (wallet + x402 agent-commerce + DEX skills)
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
