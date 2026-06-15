---
name: pharos-agent-toolkit
description: >
  A two-module Pharos Skill toolkit for the on-chain AI-agent economy.
  (1) AgentSessionWallet — a smart-contract wallet that grants an AI agent a
  time-boxed, spending-capped session key so it can act autonomously on-chain
  (transfer native PHRS or ERC-20 tokens, call any contract) while the human
  owner keeps full custody and can revoke instantly.
  (2) AgentSubscription — a recurring pull-payment primitive where a service
  provider (which may be an agent) creates a plan and a subscriber/agent joins
  once; a keeper then charges each period. The subscription layer that
  complements x402 (per-call) and the wallet (custody).
  Use this skill when the user wants to: give an agent limited spending power,
  set up an agent wallet, create a session key, cap agent daily spend, delegate
  on-chain autonomy to a bot, revoke an agent key, audit agent transactions;
  or create a subscription plan, subscribe an agent to a recurring service,
  charge recurring fees, cancel a subscription, or build an autonomous on-chain
  agent economy on Pharos. Do not attempt ERC-20 token deployment, batch
  airdrop, or generic vault/time-lock tasks — those are covered by other skills.
version: 0.2.0
network: atlantic-testnet
---

# Pharos Skill — Agent Economy Toolkit (2 modules)

A Pharos Skill package that teaches an AI agent (e.g. Claude Code) two
foundational primitives of the on-chain AI-agent economy:

1. **AgentSessionWallet** — custody: grant an agent a time-boxed, spending-capped
   session key. _"Delegate autonomy — never hand over your private key."_
2. **AgentSubscription** — recurring pull-payments: agents subscribe to services
   and get charged each period. The subscription layer that complements x402.

Together they let an agent **hold scoped funds** AND **pay for recurring
services** — the two things every autonomous agent needs.

## Prerequisites

1. **Foundry** installed (`cast` + `forge`). Check: `which cast && which forge`.
   If missing: `curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup`
2. **Private key** exported: `export PRIVATE_KEY=0x...` (the human **owner**).
   Optional second key for the agent: `export AGENT_PRIVATE_KEY=0x...`.
3. **Testnet PHRS** in the owner wallet (faucet). Check balance before writes.

## Network Configuration

All `<rpc>` placeholders are resolved from `assets/networks.json`. Default:

| Field | Value |
|---|---|
| Network | Pharos Atlantic Testnet |
| Chain ID | `688689` |
| RPC | `https://atlantic.dplabs-internal.com` |
| Explorer | `https://atlantic.pharosscan.xyz` |
| Native token | PHRS (18 decimals) |

Always pass `--rpc-url <rpc>` and `--private-key $PRIVATE_KEY` explicitly —
Foundry does **not** auto-read environment variables.

## Capability Index

> The agent scans this table to map a user's intent to the right reference
> section, then runs the exact `cast`/`forge` command found there.

### Module 1 — AgentSessionWallet (custody + session keys)

| User Need (intent + synonyms) | Capability | Detailed Instructions |
|---|---|---|
| Deploy agent wallet / set up agent session wallet / create agent custody | `forge script` + built-in template | → `references/agent-wallet.md#deploy-agentsessionwallet` |
| Verify the deployed wallet contract on the explorer | `forge verify-contract` | → `references/agent-wallet.md#verify-agentsessionwallet` |
| Fund / deposit / top up the agent wallet with PHRS | `cast send --value` | → `references/agent-wallet.md#fund-the-wallet-deposit-phrs` |
| Grant a session key for native PHRS / give agent spending power / cap agent daily spend | `cast send grantSessionKey` (token=0x0) | → `references/agent-wallet.md#grant-a-session-key-native-phrs` |
| Grant a session key for an ERC-20 token (e.g. USDC) | `cast send grantSessionKey` (token=addr) | → `references/agent-wallet.md#grant-a-session-key-erc-20` |
| Revoke / disable / kill an agent session key | `cast send revokeSessionKey` | → `references/agent-wallet.md#revoke-a-session-key-kill-switch` |
| Agent spends / transfers PHRS or tokens autonomously / execute as agent | `cast send executeAsAgent` | → `references/agent-wallet.md#execute-as-agent-autonomous-spend-within-budget` |
| Check wallet balance / how much PHRS is in the wallet | `cast call nativeBalance` | → `references/agent-wallet.md#query-wallet-balance--grant-status-free--no-gas` |
| Check if agent key is active / remaining spend budget / grant status | `cast call isSessionKeyActive` / `spendAvailable` / `getGrant` | → `references/agent-wallet.md#query-wallet-balance--grant-status-free--no-gas` |
| Owner withdraw / drain / emergency pull funds | `cast send withdraw` | → `references/agent-wallet.md#owner-escape-hatch-withdraw--drain` |
| Audit agent activity / query agent transactions / show what the agent spent | `cast logs` | → `references/agent-wallet.md#query-events-full-on-chain-audit-trail` |

### Module 2 — AgentSubscription (recurring pull-payments)

| User Need (intent + synonyms) | Capability | Detailed Instructions |
|---|---|---|
| Deploy subscription contract / set up recurring payments | `forge script` + built-in template | → `references/agent-subscription.md#deploy-agentsubscription` |
| Create a subscription plan / set up a recurring price / provider offers a service | `cast send createPlan` | → `references/agent-subscription.md#create-a-plan-provider` |
| Subscribe to a plan (ERC-20) / join a recurring service | `approve` + `subscribeERC20` | → `references/agent-subscription.md#subscribe-erc-20-plan` |
| Subscribe to a native PHRS plan / prefund recurring payments | `subscribeNative{value}` | → `references/agent-subscription.md#subscribe-native-phrs-plan--prefund` |
| Charge a period / collect a subscription fee / keeper pulls payment | `cast send charge` | → `references/agent-subscription.md#charge-a-period-provider--keeper--agent` |
| Cancel a subscription / stop recurring charges | `cast send cancel` | → `references/agent-subscription.md#cancel-subscriber-kill-switch` |
| Pause / resume a plan (provider) | `pausePlan` / `resumePlan` | → `references/agent-subscription.md#pause--resume-plan-provider` |
| When is the next charge due / is subscriber active / plan details | `secondsUntilDue` / `isSubscriberActive` / `getPlan` | → `references/agent-subscription.md#query-status--timing-free--no-gas` |
| Query subscription charges / audit recurring payments | `cast logs` | → `references/agent-subscription.md#query-events-audit-trail` |

## Write Operation Pre-checks

Before **any** `cast send` / `forge script`, verify in order:

1. **Private key** — `cast wallet address --private-key $PRIVATE_KEY` returns an address.
2. **Correct network** — `cast chain-id --rpc-url <rpc>` returns `688689`.
3. **Target address** — 42 hex chars (`0x` + 40). For the wallet, confirm code exists.
4. **Balance** — `cast balance <sender> --rpc-url <rpc> --ether` covers amount + gas.

## Security Reminders

- The **owner** key funds and manages grants. The **agent/operator** key only
  spends within limits. They are **different keys** — never reuse.
- Never hardcode a private key in a file or commit it to git. Use `$PRIVATE_KEY`.
- Session keys are powerful: always set a short `validUntil` and a tight `limit`.
- `revokeSessionKey` is the instant kill switch — show users how to use it.

## General Error Handling

| Error / Signature | Cause | Fix |
|---|---|---|
| `NotOwner` | Non-owner called an owner function | Switch to the owner `$PRIVATE_KEY` |
| `SessionKeyInactive` | No grant or grant was revoked | Owner runs `grantSessionKey` |
| `SessionKeyExpired` | `validUntil` passed | Grant a fresh key with a future expiry |
| `SpendLimitExceeded(needed, available)` | Over the per-window cap | Wait for window reset, or owner raises `limit` |
| `CallFailed(index, reason)` | An inner call reverted | Decode `reason`; check recipient/token/amount |
| `InvalidParams` | `validUntil <= now` or `period == 0` | Use a future timestamp and non-zero window |
| `ZeroAddress` | Zero passed where an address is required | Provide a real address |
| `insufficient funds` | Sender lacks gas/amount | `cast balance`, get faucet PHRS |
| `connection refused` | Missing `--rpc-url` | Always pass `--rpc-url <rpc>` explicitly |
| `forge/cast: command not found` | Foundry not installed | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` |
