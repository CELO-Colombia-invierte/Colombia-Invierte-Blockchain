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
`0x2518350C9cd1E8F45CEFe5846B4C65b4A48A5F96`

FeeManager:
`0x205AB0001A760321E474C8BAF5523AcA82E9C6B3`

FeeTreasury:
`0x84D44F50cA3043AF14C4d824c3b54C3169915aeA`

---

### Implementations (Reference / ABI Extraction)

ProjectVault Impl:
`0x4A00585cb5Bc18D893112a10d5eDB0a1836963E9`

ProjectTokenV2 Impl:
`0xd3b4480CbDEBcb4F15a7887A4f0a9D82E9400C2A`

RevenueModuleV2 Impl:
`0x9cb5d68aE667283A73007DF65ECEcA58DdD0d07d`

NatilleraV2 Impl:
`0x9298c8A103ECC9e070860629bb71a1791dc2715c`

MilestonesModule Impl:
`0x58afa3CA5119Bc7cDf0771F3F2Ca18caD08f8635`

GovernanceModule Impl:
`0x650534Dd9a41fAcbD49A8F835b6334962Dbf8324`

DisputesModule Impl:
`0x7c1219257D25F5269945D41d101722c5C214381e`

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
