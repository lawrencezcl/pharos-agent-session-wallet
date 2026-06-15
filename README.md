# AgentSessionWallet — Pharos Skill

> **Delegate limited, time-boxed, spending-capped autonomy to an AI agent on
> Pharos — without ever handing over your private key.**

A reusable **Pharos Skill** for the *Skill-to-Agent Dual Cascade Hackathon*
(Phase 1). It gives any AI agent (Claude Code, Codex, Cursor, …) a **custody
primitive** for the on-chain agent economy: a smart-contract wallet that issues
**session keys** to agents.

[![Solidity](https://img.shields.io/badge/Solidity-^0.8.24-363636?logo=solidity)]()
[![Foundry](https://img.shields.io/badge/Foundry-1.7.x-ff7a18?logo=foundry)]()
[![Tests](https://img.shields.io/badge/tests-17%20passed-brightgreen)]()
[![Network](https://img.shields.io/badge/Pharos-Atlantic%20Testnet-688689-blue)]()

---

## Why this skill?

Every Phase-2 agent that transacts on Pharos needs **a wallet it can control**.
But a real AI agent should **never** hold a user's full private key — that's how
funds get drained. The 2026 state-of-the-art answer (Coinbase Smart Wallet,
Alchemy Account Kit) is the **session key**: a separate, throwaway key granted
**scoped** autonomy.

`AgentSessionWallet` brings that pattern to Pharos as a composable Skill:

| Feature | What it gives an agent |
|---|---|
| **Session keys** | An agent EOA that can spend **only** what the owner allows |
| **Time-boxed** | Hard `validUntil` expiry — agents can't run forever |
| **Spending caps** | Per-token `limit` over a rolling `period` (e.g. 1 PHRS/day) |
| **Window reset** | Budget refreshes automatically each period |
| **Instant revoke** | One owner tx kills a key — the kill switch |
| **Batching** | `executeAsAgent` runs a batch of calls in one tx (gas-efficient) |
| **Composable** | Wallet can call **any** contract — x402, airdrop, vault, DEX, … |
| **Full audit trail** | Every action emits events queryable with `cast logs` |
| **Escape hatch** | Owner can drain native + ERC-20 at any time |

It composes with the rest of the Pharos ecosystem: the owner can grant a native
key for gas + an ERC-20 (e.g. test USDC) key for x402 agent-commerce, all in one
wallet.

---

## Repository layout

```
.
├── SKILL.md                       # AI-agent entry point + Capability Index
├── assets/
│   ├── networks.json              # RPC, chain ID, explorer (Atlantic testnet)
│   ├── tokens.json                # PHRS, test USDC, canonical contracts
│   └── agent-wallet/
│       └── AgentSessionWallet.sol # the contract template (also in src/)
├── references/
│   └── agent-wallet.md            # machine-readable ops manual for the agent
├── src/AgentSessionWallet.sol     # foundry source (compiles + tests)
├── script/DeployAgentSessionWallet.s.sol
├── test/AgentSessionWallet.t.sol  # 17 passing tests
├── foundry.toml
├── demo/
│   └── demo-session-flow.sh       # end-to-end demo against a local anvil node
└── .env.example
```

This repo **is** the Skill package — clone it, point Claude Code at it, and ask
in natural language.

---

## Quick start

### 1. Install Foundry + configure keys
```bash
curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup
cp .env.example .env            # fill in OWNER and AGENT private keys
source .env
```

### 2. Compile & test
```bash
forge build
forge test -vv                  # 17 tests, all green
```

### 3. Use it with an AI agent (Claude Code)
```bash
cd AgentSessionWallet
claude
# then say:
#   "Deploy an agent session wallet on Pharos and grant my agent 0.5 PHRS/day for 1 day"
```
The agent reads `SKILL.md`, finds the matching Capability Index rows, follows
`references/agent-wallet.md`, and runs the exact `cast`/`forge` commands.

### 4. (Or) drive it manually
```bash
# Deploy
forge script script/DeployAgentSessionWallet.s.sol:DeployAgentSessionWallet \
  --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast

# Fund
cast send <wallet> --value 1ether --private-key $PRIVATE_KEY --rpc-url $RPC

# Grant a daily 0.5 PHRS key to the agent (valid 1 day)
cast send <wallet> "grantSessionKey(address,address,uint96,uint64,uint256)" \
  $AGENT 0x0000000000000000000000000000000000000000 \
  $(($(date +%s)+86400)) 86400 500000000000000000 \
  --private-key $PRIVATE_KEY --rpc-url $RPC

# Agent spends (uses $AGENT_PRIVATE_KEY, not the owner key!)
cast send <wallet> "executeAsAgent((address,uint256,bytes)[])" \
  "[(<recipient>, 100000000000000000, 0x)]" \
  --private-key $AGENT_PRIVATE_KEY --rpc-url $RPC
```

---

## The mental model

```
   HUMAN OWNER                          AI AGENT
   (full custody)                       (runtime)
        │                                  │
        │  grantSessionKey(operator,       │
        │     token=PHRS, +1day,           │
        │     limit=0.5 PHRS/day)          │
        ├──────────────► WALLET ◄──────────┤
        │                 │   executeAsAgent(calls)
        │                 │   └ checks: active? expired? within budget?
        │                 └──────► recipient / token / any contract
        │
        │  revokeSessionKey(...)   ◄── instant kill switch
        │  withdraw(...)           ◄── escape hatch anytime
```

The agent **never** sees the owner key. It can only do what the grant allows.

---

## How scoring criteria are met

| Judging criterion | How this skill delivers |
|---|---|
| **Originality** | First session-key/custody skill for Pharos; not a built-in (ERC20/airdrop/vault) |
| **Technical quality** | Audited-style error handling, reentrancy-safe batching, 17 unit tests, rolling-window math |
| **Practical use case** | The core primitive every autonomous agent needs before it can spend |
| **Reusability / composability** | Wallet calls **any** contract — composes with x402, vault, airdrop, DEX skills |
| **Deployment on Pharos** | Compiles & verifies on Atlantic testnet (chain 688689) via Foundry |
| **Docs & UX** | Natural-language driven; full `SKILL.md` + `references/` + demo script |
| **Agent-economy alignment** | Directly enables delegated on-chain autonomy — Pharos's stated vision |

---

## Local demo (no testnet PHRS needed)
```bash
./demo/demo-session-flow.sh      # spins up anvil and runs the full flow
```

---

## License
MIT
