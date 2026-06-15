# Project Summary / 项目总结

> Pharos "Skill-to-Agent Dual Cascade" Hackathon — Phase 1 submission
> Repo: https://github.com/lawrencezcl/pharos-agent-session-wallet

---

# 🇬🇧 English Summary

## What we built
A **two-module Pharos Skill toolkit** for the on-chain AI-agent economy:

| # | Module | Role | One-liner |
|---|---|---|---|
| 1 | **AgentSessionWallet** | Custody | Grant an AI agent a time-boxed, spending-capped session key — full autonomy, zero private-key exposure |
| 2 | **AgentSubscription** | Recurring payments | Pull-payment subscriptions: an agent subscribes to a service and gets charged each period, revocable anytime |

Together they let an autonomous agent **hold scoped funds** AND **pay for
recurring services** — the two primitives every spending agent needs. They
complement x402 (per-call micropayments) and the built-in skills (ERC20, airdrop,
vault).

## Status

| Stage | State |
|---|---|
| Design | ✅ Done |
| Build (contracts + skill package) | ✅ Done |
| Test | ✅ **33/33 tests pass** (17 wallet + 16 subscription) |
| Local demos (anvil, chain 688689) | ✅ Both verified end-to-end |
| GitHub repo (public) | ✅ Pushed (3 commits) |
| BUIDL content | ✅ Ready (`BUIDL.md`, copy-paste) |
| One-shot testnet script | ✅ Ready (`scripts/live-deploy-and-demo.sh`, balance-gated) |
| **Live testnet deploy** | ⏸️ **Blocked** — owner wallet has 0 PHRS; all faucets are captcha-gated (no programmatic claim) |
| **DoraHacks submission** | ⏸️ **Blocked** — site behind AWS WAF captcha + needs your authenticated login |

## Repo
**https://github.com/lawrencezcl/pharos-agent-session-wallet** (account
`lawrencezcl`)

```
SKILL.md                      # entry point + dual Capability Index
assets/{agent-wallet,agent-subscription}/*.sol   # contract templates
references/{agent-wallet,agent-subscription}.md  # AI ops manuals
src/*.sol  script/*.s.sol  test/*.t.sol          # foundry project (33 tests)
demo/demo-*-flow.sh           # local anvil demos (both modules)
scripts/live-deploy-and-demo.sh  # one-shot testnet deploy+demo
BUIDL.md  README.md
```

## The 2 hard blockers (need a human in a browser)
1. **Testnet PHRS** — all Pharos faucets (ZAN, gas.zip, OmniHub, official portal)
   are captcha-gated. Verified: no programmatic API. Owner balance is 0.
2. **DoraHacks submit** — behind AWS WAF "Human Verification"; needs your own
   DoraHacks login (GitHub OAuth / email). Cannot submit on your behalf.

## Your 2-minute finish path
1. **Claim ~0.5 PHRS** at https://zan.top/faucet/pharos → send to
   `0xB4e53D8c5945361e2aC392245Ea322D57980462C` (owner wallet; key in `.env`).
2. **Say "funded"** → I run `./scripts/live-deploy-and-demo.sh`: deploys +
   verifies both contracts, runs the full agent flow, and pastes explorer links
   into `BUIDL.md`.
3. **Submit on DoraHacks**: log in → "Submit BUIDL" → paste `BUIDL.md` +
   repo link (everything is pre-written; only the final click is yours).

## Keys & security
- Owner + agent private keys generated and stored in `.env` (**gitignored**,
  never committed — verified).
- ⚠️ The GitHub token shared in chat is now in history — **rotate it** after we finish.

---

# 🇨🇳 中文总结

## 我们构建了什么
一套面向链上 AI 智能体经济的**双模块 Pharos Skill 工具包**：

| # | 模块 | 职能 | 一句话 |
|---|---|---|---|
| 1 | **AgentSessionWallet**（智能体钱包） | 资金托管 | 给 AI 智能体颁发有时限、有消费上限的"会话密钥"——完全自主，但永不暴露主私钥 |
| 2 | **AgentSubscription**（订阅支付） | 周期付费 | 拉款式订阅：智能体订阅某项服务，每个周期被自动扣费，可随时取消 |

两者合起来，让一个自主智能体既能**持有限额资金**，又能**为周期性服务付费**——这是每个会花钱的智能体都需要的两大基础能力。它们与 x402（按次微支付）和官方内置技能（ERC20、空投、金库）形成互补。

## 当前状态

| 阶段 | 状态 |
|---|---|
| 设计 | ✅ 完成 |
| 构建（合约 + 技能包） | ✅ 完成 |
| 测试 | ✅ **33/33 全部通过**（钱包 17 + 订阅 16） |
| 本地演示（anvil，链 ID 688689） | ✅ 两个模块均端到端验证 |
| GitHub 仓库（公开） | ✅ 已推送（3 次提交） |
| BUIDL 提交文案 | ✅ 就绪（`BUIDL.md`，可直接复制粘贴） |
| 测试网一键部署脚本 | ✅ 就绪（`scripts/live-deploy-and-demo.sh`，含余额检查） |
| **测试网实际部署** | ⏸️ **受阻** —— owner 钱包余额为 0，所有水龙头都需人机验证（无法程序化领取） |
| **DoraHacks 提交** | ⏸️ **受阻** —— 网站有 AWS WAF 人机验证 + 需要你本人登录账号 |

## 仓库地址
**https://github.com/lawrencezcl/pharos-agent-session-wallet**（账号 `lawrencezcl`）

```
SKILL.md                      # 入口 + 双技能能力索引
assets/{agent-wallet,agent-subscription}/*.sol   # 合约模板
references/{agent-wallet,agent-subscription}.md  # 给 AI 的操作手册
src/*.sol  script/*.s.sol  test/*.t.sol          # Foundry 工程（33 个测试）
demo/demo-*-flow.sh           # 本地 anvil 演示（两个模块）
scripts/live-deploy-and-demo.sh  # 测试网一键部署+演示
BUIDL.md  README.md
```

## 两个无法自动化的硬性卡点（需要人在浏览器里操作）
1. **测试网 PHRS** —— Pharos 所有水龙头（ZAN、gas.zip、OmniHub、官方门户）都有人机验证。已核实：无程序化 API。owner 余额为 0。
2. **DoraHacks 提交** —— 网站受 AWS WAF "Human Verification" 拦截，且需要你本人的 DoraHacks 登录态（GitHub 授权 / 邮箱登录）。无法代你提交。

## 你的 2 分钟收尾步骤
1. **领取约 0.5 PHRS**：打开 https://zan.top/faucet/pharos → 发送到
   `0xB4e53D8c5945361e2aC392245Ea322D57980462C`（owner 钱包；私钥已在 `.env`）。
2. **回复 "funded"** → 我运行 `./scripts/live-deploy-and-demo.sh`：部署 +
   验证两个合约、跑完整智能体流程，并把浏览器链接贴进 `BUIDL.md`。
3. **在 DoraHacks 提交**：登录 → "Submit BUIDL" → 粘贴 `BUIDL.md` 内容 +
   仓库链接（文案已全部写好，只剩最后那一下点击）。

## 密钥与安全
- owner 与 agent 私钥已生成并存于 `.env`（**已加入 .gitignore，从未提交**——已核实）。
- ⚠️ 对话中提供的 GitHub token 已留在聊天记录里 —— **完成后请立即轮换**。

---

*Generated for the Pharos Phase-1 Skill Hackathon · toolkit v0.2.0*
