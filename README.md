# Colombia Invierte — Platform Contracts (MVP V2)

> **Status:** Deployed on Celo Sepolia
> **Architecture:** Modular — Project-Isolated
> **Network:** Celo Sepolia (Chain ID: 11142220)

MVP V2 is the modular evolution of the Colombia Invierte protocol.

Unlike MVP V1 (monolithic), V2 introduces:

- Per-project isolated custody (Vaults)
- Modular financial logic
- On-chain governance and explicit dispute state machines
- Dual investment models with equal importance:

  - **Tokenization** (ERC20 + revenue distribution)

  - **Natillera** (Collective savings cycles)

This version is architected for production-readiness while keeping clarity, economic security, and composability as first-class priorities.

---

# High-Level Architecture

Each project deployed through `PlatformV2` is isolated and composed of multiple modules.

Core flow:

```
PlatformV2 (Factory)
        │
        ├── ProjectVault (Custody - Source of Truth)
        ├── RevenueModuleV2 / NatilleraV2 (Financial Logic)
        ├── MilestonesModule (Optional, Tokenization)
        ├── GovernanceModule (Execution & Consensus)
        └── DisputesModule (Emergency & Freeze)
```

No funds are ever stored in the factory. Every project has its own Vault and dedicated modules.

---

# Supported Investment Models

## 1️⃣ Tokenization Model

Users invest stablecoins and receive ERC20 project tokens.

Flow:

- Investor approves stablecoin
- Calls `invest()` on RevenueModuleV2
- Funds go to ProjectVault (Strict multiple validation prevents dust loss).
- Tokens are minted proportionally
- Revenue can later be deposited and claimed via MasterChef-style accounting (O(1) complexity).

Governance: Uses RevenueVoting (1 Token = 1 Vote) based on ERC20Votes.

Components:

- `ProjectTokenV2`
- `RevenueModuleV2`
- `ProjectVault`
- `MilestonesModule`
- `GovernanceModule`
- `DisputesModule`
- `RevenueVoting`

---

## 2️⃣ Natillera Model (Collective Savings)

Members join a savings circle and contribute periodic quotas.

Flow:

- Member joins via `join()`
- Pays monthly quotas via `payQuota(monthId)`
- Late payments may include penalties
- Yield Generation: Governance can propose a Disbursement to invest funds off-chain. Returns are injected back via `returnYield()`.
- After cycle completion, fees are settled and members withdraw their proportional share + yields.

Governance: Uses NatilleraVoting (1 Member = 1 Vote) for democratic consensus.

Components:

- `NatilleraV2`
- `ProjectVault`
- `GovernanceModule`
- `DisputesModule`
- `NatilleraVoting`

Natillera does not mint ERC20 tokens.

---

# Core Contracts

## PlatformV2

Factory contract responsible for creating new projects and wiring access control. Once deployed, the factory revokes its own admin rights, ensuring true decentralization.

Responsibilities:

- Creating new projects
- Deploying isolated modules
- Emitting `ProjectCreated` event with all module addresses

It holds no user funds.

---

## ProjectVault

Per-project custody contract. Holds all funds, enforces state transitions, and protects minimum reserves for protocol fees.

Responsibilities:

- Receive deposits
- Track funds
- Release funds when authorized
- Close project lifecycle

All economic flows pass through the Vault.

---

## RevenueModuleV2

Handles:

- Investment logic
- Token minting
- Revenue deposits
- Claiming of earnings
- Refunds (if softcap not reached)

---

## NatilleraV2

Handles:

- Member registration
- Monthly quota payments
- Penalties
- Final proportional distribution

---

## MilestonesModule

Optional module for Tokenization projects.

Used to:

- Gate fund releases
- Require approvals before capital deployment

---

## GovernanceModule & Voting Strategies

Minimal on-chain governance layer. Uses immutable parameter snapshots (endTime, quorum) to prevent temporal manipulation during active votes. Supports milestones, disbursements, and parameter updates.

Supports:

- Proposal creation
- Voting
- Weighted voting logic

---

## DisputesModule

Emergency and conflict resolution module. Uses an explicit state machine (activeDisputeId) interacting with the Vault to freeze funds and prevent Guardian overriding.

Supports:

- Opening disputes
- Resolving and resuming operations

---

## FeeManager & FeeTreasury

- FeeManager: Dynamically calculates and routes protocol fees (e.g., 30% Tokenization, 3% Natillera).
- FeeTreasury: Secure receiver for protocol-level fees.

Project funds remain isolated in their Vault.

---

# Deployment — Celo Sepolia

**Chain ID:** 11142220

### Core Contracts

PlatformV2:
`0x35f7CA6a328cECef2984fbF933c4D01d2632c4a6`

FeeManager:
`0x6F30Fd58E539949D34ba68374D150Fb86104071C`

FeeTreasury:
`0x3aa898F6B1530B45Ed785F9C5CdB626dfF03682d`

---

### Implementations (Reference / ABI Extraction)

ProjectVault Impl:
`0x0A823B0af40380A13bba5851A501672D9Ef7aF74`

ProjectTokenV2 Impl:
`0xE233D5dF4e8A93e885674A81401e5C165577D45b`

RevenueModuleV2 Impl:
`0x17f2CED2Be89175BE194FcC0F006e9f54f39b4d7`

NatilleraV2 Impl:
`0x42ae916Ee9F4bD3bb9767fE6AF9579CB5F19324b`

MilestonesModule Impl:
`0x5A83256310F2853cF435D55d188a5501025e1cfB`

GovernanceModule Impl:
`0x430f467bb254Cd356BE06cFB7581d1Ef69f1fBC5`

DisputesModule Impl:
`0x617Fea7bf726741166B5609239ef952293118a15`

---

# Development

This repository uses Foundry.

### Install

```bash
forge install
```

### Build

```bash
forge build
```

### Run Tests

```bash
forge test -vv
```

### Gas Report

```bash
forge test --gas-report
```

---

# Project Lifecycle

1. Project created via PlatformV2
2. Vault initialized
3. Users interact with RevenueModule or Natillera
4. Funds accumulated in Vault
5. Governance / Milestones (if applicable)
6. Project closed
7. Final claims or withdrawals

---

# Security Principles

- Least Privilege Access: Strict CONTROLLER_ROLE and GUARDIAN_ROLE enforcement.
- Explicit State Machines: No ambiguous pause states during disputes.
- Temporal Immutability: Proposals lock their governance parameters upon creation.
- Precision Loss Prevention: Strict modulo checks on investments.
- Event-Driven Indexing: Full off-chain traceability via granular events.

---

# Backend & Frontend Integration

V2 is fully dynamic and event-driven.

Backend must:

- Listen to ProjectCreated, dynamically instantiate cloned contracts, and map descriptionHash to off-chain IPFS/DB data.

Frontend must:

- Never hardcode module addresses. Fetch them from the backend and use BigInt for all EVM interactions.

---

# Disclaimer

This deployment is currently on Celo Sepolia testnet. Mainnet deployment will require a final security review, multisig administration setup, and real-world economic simulation validation. Use at your own risk.

---

# Versioning

- MVP V1: Frozen (monolithic)
- MVP V2: Modular architecture
- Future versions will follow semantic versioning

---
