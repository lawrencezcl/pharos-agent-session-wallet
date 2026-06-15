# AgentSessionWallet Operation Instructions

> **Network Configuration**: The `<rpc>` value in every command is read from the
> `networks.<network>.rpcUrl` field in `assets/networks.json`. Default network is
> `atlantic-testnet` (`https://atlantic.dplabs-internal.com`, chain ID `688689`).
>
> **Private Key Configuration**: Foundry does **not** auto-read env vars. Every
> write command must pass the key explicitly as `--private-key $PRIVATE_KEY`.
> Always pass `--rpc-url <rpc>` explicitly.
>
> **Symbol**: Native token is **PHRS** (18 decimals).

This skill lets an AI agent deploy and operate an **AgentSessionWallet** — a
smart-contract wallet that grants an agent a **time-boxed, spending-capped
session key**. The agent can transfer native PHRS or ERC-20 tokens, and call any
contract, within the scoped budget; the human owner keeps full custody and can
revoke instantly.

---

## Core Concepts (read this before running anything)

| Concept | Meaning |
|---|---|
| **owner** | The human deployer. Has unrestricted power: `execute`, `withdraw`, `grantSessionKey`, `revokeSessionKey`. |
| **operator (session key)** | A normal EOA private key the AI agent's runtime controls. Never the owner's key. |
| **grant** | Per `(operator, token)` permission: hard expiry `validUntil`, rolling window `period`, per-window `limit`, running `spent`. `token = 0x0` means native PHRS. |
| **executeAsAgent** | The function the operator calls to act. Each spend is checked against its own grant. Native spend = `Call.value`; ERC-20 spend = detected `transfer(address,uint256)` selector (`0xa9059cbb`) on the token. |
| **execute** | Owner-only escape hatch; no limits. |

---

## Deploy AgentSessionWallet

### Overview
Deploys the wallet. The deployer becomes the `owner` unless `OWNER_ADDRESS` is
set. The owner is the only account that can grant/revoke session keys and drain
funds — keep this key safe.

### Step 1: Generate Deployment Script
The Agent copies `assets/agent-wallet/AgentSessionWallet.sol` to the user's
project at `src/AgentSessionWallet.sol` and generates
`script/DeployAgentSessionWallet.s.sol` (a copy ships with this skill).

### Step 2: Execute Deployment

**Command Template**
```bash
forge script script/DeployAgentSessionWallet.s.sol:DeployAgentSessionWallet \
  --rpc-url <rpc> \
  --private-key $PRIVATE_KEY \
  --broadcast
```

**Parameters**
| Parameter | Type | Required | Description |
|---|---|---|---|
| `OWNER_ADDRESS` | address | No | Wallet owner. Defaults to the deployer (`msg.sender`). Export it first if you want a different owner. |
| `--rpc-url` | string | Yes | RPC endpoint from `assets/networks.json` |
| `--private-key` | string | Yes | Deployer key via `$PRIVATE_KEY` |

**Output Parsing**
| Field | Description |
|---|---|
| `Wallet address:` | Deployed contract address — save this; every later command needs it |
| `Owner:` | The custody address (can grant/revoke keys) |
| `Chain ID:` | Should be `688689` on Atlantic testnet |

**Error Handling**
| Error | Cause | Fix |
|---|---|---|
| `insufficient funds` | Deployer lacks gas | `cast balance <deployer> --rpc-url <rpc> --ether`, get faucet PHRS |
| `compiler error` | Source missing/old solc | Confirm `foundry.toml` solc `^0.8.24`; run `foundryup` |
| `connection refused` | Missing/unreachable `--rpc-url` | Pass `--rpc-url <rpc>` explicitly |

> **Agent Guidelines:**
> 1. Complete "Write Operation Pre-checks" (see `SKILL.md`)
> 2. Confirm `cast --version` and `forge --version` exist; install Foundry if missing
> 3. Read `rpcUrl` + `chainId` from `assets/networks.json`
> 4. Check deployer balance: `cast balance <deployer> --rpc-url <rpc> --ether`
> 5. Copy `assets/agent-wallet/AgentSessionWallet.sol` → `src/AgentSessionWallet.sol`
> 6. Run `forge script` with `--rpc-url`, `--private-key $PRIVATE_KEY`, `--broadcast`
> 7. Extract `Wallet address:` from output; show explorer link `<explorerUrl>/address/<wallet>`
> 8. Ask if user wants to verify (see next section). If yes, `sleep 10` first.

---

## Verify AgentSessionWallet

**Command Template**
```bash
sleep 10
forge verify-contract <wallet_address> src/AgentSessionWallet.sol:AgentSessionWallet \
  --chain-id 688689 \
  --verifier-url https://api.socialscan.io/pharos-atlantic-testnet/v1/explorer/command_api/contract \
  --verifier blockscout \
  --constructor-args $(cast abi-encode "constructor(address)" <owner_address>)
```

**Parameters**
| Parameter | Type | Required | Description |
|---|---|---|---|
| `<wallet_address>` | address | Yes | From the deploy step |
| `<owner_address>` | address | Yes | The owner printed at deploy (needed for constructor args) |

**Error Handling**
| Error | Cause | Fix |
|---|---|---|
| `contract not found` | Explorer not indexed yet | Wait 10–15s and retry |
| `verification failed` | Source/compiler mismatch | Confirm solc `^0.8.24` in `foundry.toml` |

---

## Fund the Wallet (Deposit PHRS)

Anyone can top up the wallet by sending native PHRS. This is **free for the
sender's intent** but is itself a transaction (costs gas).

**Command Template**
```bash
cast send <wallet_address> --value <amount>ether \
  --private-key $PRIVATE_KEY --rpc-url <rpc>
```

**Parameters**
| Parameter | Required | Description |
|---|---|---|
| `<amount>` | Yes | PHRS to deposit, e.g. `0.5ether`, `1ether` |

**Output Parsing**
| Field | Description |
|---|---|
| `status` | `1` = success |

> **Agent Guidelines:** Check sender balance first. After success show
> `<explorerUrl>/tx/<txHash>`. Then read wallet balance with the `nativeBalance`
> query below to confirm.

---

## Grant a Session Key (native PHRS)

Gives an operator key permission to spend native PHRS up to `limit` per rolling
`period` window, expiring at `validUntil`. Owner-only.

**Command Template**
```bash
cast send <wallet_address> "grantSessionKey(address,address,uint96,uint64,uint256)" \
  <operator> <0x0000000000000000000000000000000000000000> <validUntil> <period> <limit> \
  --private-key $PRIVATE_KEY --rpc-url <rpc>
```

**Parameters**
| Parameter | Type | Required | Description |
|---|---|---|---|
| `<operator>` | address | Yes | The agent's runtime EOA |
| token | address | Yes | `0x0000...0000` for native PHRS |
| `<validUntil>` | uint96 | Yes | Unix seconds; must be > now. e.g. `$(($(date +%s) + 86400))` = +1 day |
| `<period>` | uint64 | Yes | Window seconds. `86400` = daily, `3600` = hourly |
| `<limit>` | uint256 | Yes | Max wei per window. e.g. `1000000000000000000` = 1 PHRS/day |

**Output Parsing**
| Field | Description |
|---|---|
| `status` | `1` = granted |

**Error Handling**
| Error | Cause | Fix |
|---|---|---|
| `NotOwner` | Caller isn't owner | Use the owner's `$PRIVATE_KEY` |
| `InvalidParams` | `validUntil <= now` or `period == 0` | Use a future timestamp and non-zero period |

> **Agent Guidelines:**
> 1. Confirm caller is the owner (`cast call <wallet> "owner()(address)" --rpc-url <rpc>`)
> 2. Ask user for `validUntil`, `period`, `limit`. Suggest defaults: `+1 day`, `86400`, `1 PHRS`.
> 3. Compute `validUntil = $(date +%s) + 86400` and `limit = 1 * 10^18`.
> 4. After broadcast, query `getGrant` (below) to show the user the active grant.

---

## Grant a Session Key (ERC-20)

Same as native, but `token` = the ERC-20 contract address and `limit` uses the
token's decimals. **Also deposit tokens into the wallet** (the wallet calls
`transfer` from its own balance).

**Command Template**
```bash
# 1. Grant (owner)
cast send <wallet_address> "grantSessionKey(address,address,uint96,uint64,uint256)" \
  <operator> <token_address> <validUntil> <period> <limit> \
  --private-key $PRIVATE_KEY --rpc-url <rpc>

# 2. Move ERC-20 tokens the wallet will spend into the wallet (owner -> wallet)
cast send <token_address> "transfer(address,uint256)" <wallet_address> <amount> \
  --private-key $PRIVATE_KEY --rpc-url <rpc>
```

> **Agent Guidelines:** For USDC (test) use address
> `0xE0BE08c77f415F577A1B3A9aD7a1Df1479564ec8` and **6 decimals**, so
> `limit = 1000000` means 1 USDC. Confirm token decimals via
> `cast call <token> "decimals()(uint8)" --rpc-url <rpc>`.

---

## Revoke a Session Key (kill switch)

Instantly disables a grant. Owner-only. Use when the agent misbehaves or the key
may be compromised.

**Command Template**
```bash
cast send <wallet_address> "revokeSessionKey(address,address)" \
  <operator> <token_or_zero> \
  --private-key $PRIVATE_KEY --rpc-url <rpc>
```

> **Agent Guidelines:** After revoke, show
> `isSessionKeyActive(operator,token)` returning `false`.

---

## Execute as Agent (autonomous spend within budget)

This is what the AI **agent** calls. It can batch native transfers and ERC-20
transfers. Each spend is enforced against its grant.

### Single native transfer
```bash
cast send <wallet_address> "executeAsAgent((address,uint256,bytes)[])" \
  "[(<recipient>, <amount>, 0x)]" \
  --private-key $AGENT_PRIVATE_KEY --rpc-url <rpc>
```

### Single ERC-20 transfer
```bash
# Encode the inner ERC-20 transfer calldata
TOKEN_DATA=$(cast calldata "transfer(address,uint256)" <recipient> <amount>)
cast send <wallet_address> "executeAsAgent((address,uint256,bytes)[])" \
  "[(<token_address>, 0, $TOKEN_DATA)]" \
  --private-key $AGENT_PRIVATE_KEY --rpc-url <rpc>
```

> **`$AGENT_PRIVATE_KEY`** is the **operator** key, NOT the owner's. This is the
> whole point: the agent never touches the owner key.

**Error Handling**
| Error | Cause | Fix |
|---|---|---|
| `SessionKeyInactive` | No grant, or revoked | Owner runs `grantSessionKey` |
| `SessionKeyExpired` | Past `validUntil` | Owner grants a fresh key |
| `SpendLimitExceeded(needed, available)` | Over per-window budget | Wait for window reset, or owner raises `limit` |
| `CallFailed(index, reason)` | Inner call reverted | Decode `reason`; e.g. ERC-20 returned false |

> **Agent Guidelines:**
> 1. Before spending, check `spendAvailable(operator, token)` (below). If `< amount`, tell the user to wait or raise the limit.
> 2. Use the **operator** key, never the owner key.
> 3. After success show `<explorerUrl>/tx/<txHash>` and the new `spendAvailable`.

---

## Query: wallet balance & grant status (free — no gas)

### Native balance held by the wallet
```bash
cast call <wallet_address> "nativeBalance()(uint256)" --rpc-url <rpc>
# Convert wei -> PHRS: cast --to-unit <value> ether   (or divide by 1e18)
```

### Owner of the wallet
```bash
cast call <wallet_address> "owner()(address)" --rpc-url <rpc>
```

### Is a session key active right now?
```bash
cast call <wallet_address> "isSessionKeyActive(address,address)(bool)" \
  <operator> <token_or_zero> --rpc-url <rpc>
```

### Remaining spend budget this window
```bash
cast call <wallet_address> "spendAvailable(address,address)(uint256)" \
  <operator> <token_or_zero> --rpc-url <rpc>
```

### Full grant state
```bash
cast call <wallet_address> "getGrant(address,address)(uint96,uint64,uint64,uint256,uint256)" \
  <operator> <token_or_zero> --rpc-url <rpc>
# Returns: validUntil, period, windowStart, limit, spent
```

---

## Owner Escape Hatch: withdraw / drain

Owner pulls native or ERC-20 out at any time, bypassing all limits.

```bash
# Native
cast send <wallet_address> "withdraw(address,uint256,address)" \
  0x0000000000000000000000000000000000000000 <amount> <to> \
  --private-key $PRIVATE_KEY --rpc-url <rpc>

# ERC-20
cast send <wallet_address> "withdraw(address,uint256,address)" \
  <token_address> <amount> <to> \
  --private-key $PRIVATE_KEY --rpc-url <rpc>
```

---

## Query Events (full on-chain audit trail)

### Session key granted
```bash
cast logs --rpc-url <rpc> --address <wallet_address> \
  "SessionKeyGranted(address,address,uint256,uint64,uint256)"
```

### Spend consumed (every agent action)
```bash
cast logs --rpc-url <rpc> --address <wallet_address> \
  "SessionKeyConsumed(address,address,uint256,uint256,uint256,uint256)"
# topics[1]=operator, topics[2]=token, data=[amount, totalSpentInWindow, windowStart]
```

### Executed batches
```bash
cast logs --rpc-url <rpc> --address <wallet_address> \
  "Executed(address,bool,uint256,bytes32)"
```

### Deposits / Withdrawals
```bash
cast logs --rpc-url <rpc> --address <wallet_address> "Deposited(address,uint256)"
cast logs --rpc-url <rpc> --address <wallet_address> "Withdrawn(address,address,uint256)"
```

> **Agent Guidelines:** Convert wei → PHRS (÷1e18) and unix timestamps → human
> dates. Include `<explorerUrl>/tx/<txHash>` for each event. This audit trail is
> how a human verifies what their agent did.

---

## End-to-End Test Sequence (recommended order)

1. **Deploy** (owner key) → save `<wallet>`
2. **Fund**: send 1 PHRS to `<wallet>`
3. **Grant** native key: operator=`<agent>`, +1 day, daily, 1 PHRS/day
4. **Check** `spendAvailable(agent, 0x0)` → `1000000000000000000`
5. **Agent spends** 0.4 PHRS via `executeAsAgent` (operator key)
6. **Check** `spendAvailable` → `600000000000000000` (0.6 left)
7. **Try over-spend** 0.7 PHRS → reverts `SpendLimitExceeded`
8. **Revoke** (owner key) → agent can no longer spend
9. **Query** `SessionKeyConsumed` logs → show the audit trail
