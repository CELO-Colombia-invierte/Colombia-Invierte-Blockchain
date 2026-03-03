# Colombia Invierte — Platform Contracts (MVP V2)

> **Status:** Deployed on Celo Sepolia
> **Architecture:** Modular — Project-Isolated
> **Network:** Celo Sepolia (Chain ID: 11142220)

MVP V2 is the modular evolution of the Colombia Invierte protocol.

Unlike MVP V1 (monolithic), V2 introduces:

- Per-project isolated custody
- Modular financial logic
- On-chain governance and disputes
- Dual investment models with equal importance:

  - Tokenization (ERC20 + revenue distribution)
  - Natillera (collective savings cycles)

This version is architected for production-readiness while keeping clarity and composability as first-class priorities.

---

# High-Level Architecture

Each project deployed through `PlatformV2` is isolated and composed of multiple modules.

Core flow:

```
PlatformV2 (Factory)
        │
        ├── ProjectVault (Custody)
        ├── RevenueModuleV2 (Tokenization model)
        ├── NatilleraV2 (Savings model)
        ├── MilestonesModule (Optional, Tokenization)
        ├── GovernanceModule
        └── DisputesModule
```

No funds are ever stored in the factory.

Every project has its own Vault and dedicated modules.

---

# Supported Investment Models

## 1️⃣ Tokenization Model

Users invest stablecoins and receive ERC20 project tokens.

Flow:

- Investor approves stablecoin
- Calls `invest()` on RevenueModuleV2
- Funds go to ProjectVault
- Tokens are minted proportionally
- Revenue can later be deposited and claimed

Components:

- `ProjectTokenV2`
- `RevenueModuleV2`
- `ProjectVault`
- `MilestonesModule` (optional)

---

## 2️⃣ Natillera Model (Collective Savings)

Members join a savings circle and contribute periodic quotas.

Flow:

- Member joins via `join()`
- Pays monthly quotas via `payQuota(monthId)`
- Late payments may include penalties
- After cycle completion and Vault closure:

  - Members withdraw their proportional share

Components:

- `NatilleraV2`
- `ProjectVault`

Natillera does not mint ERC20 tokens.

---

# Core Contracts

## PlatformV2

Factory contract responsible for:

- Creating new projects
- Deploying isolated modules
- Emitting `ProjectCreated` event with all module addresses

It holds no user funds.

---

## ProjectVault

Per-project custody contract.

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

## GovernanceModule

Minimal on-chain governance layer.

Supports:

- Proposal creation
- Voting
- Weighted voting logic

---

## DisputesModule

Emergency and conflict resolution module.

Supports:

- Opening disputes
- Pausing project logic
- Resolving and resuming operations

---

## FeeManager & FeeTreasury

- FeeManager: Calculates and routes protocol fees
- FeeTreasury: Receives protocol-level fees

Project funds remain isolated in their Vault.

---

# Deployment — Celo Sepolia

**Chain ID:** 11142220

### Core Contracts

PlatformV2:
`0xd6BA650Fb9426508707E77e8fb58037B39723F69`

FeeManager:
`0x36e23fE797F04C5197A713B29508C80b5b9f25aa`

FeeTreasury:
`0x8392dD63883Fc5566e54B3431E35bA100D10Ae86`

---

### Implementations (Reference / ABI Extraction)

ProjectVault Impl:
`0x5057e98c1fbe4356f45d3aB6DEb500a544b547c9`

ProjectTokenV2 Impl:
`0x0F7F23226666E8DF6E170933A0082B5c6774Aeb3`

RevenueModuleV2 Impl:
`0x1e29a3952EB6cE8919B8925807DBfE0f4dAB4cd4`

NatilleraV2 Impl:
`0xC9A8e53168e6Aed3d1Ded5CBC756F84f834771Fd`

MilestonesModule Impl:
`0x840DBE5f1D117b8806C92C77131691DbCB83e043`

GovernanceModule Impl:
`0x604b58C93a02D49a8f603F8AF086F8b9E3727839`

DisputesModule Impl:
`0x092A096E486504B678e904537455c31f0fBdd413`

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

- Isolated custody per project
- No funds in factory
- Explicit state transitions
- Event-driven indexing
- Emergency dispute mechanism
- Refund path for failed funding (Tokenization)

---

# Backend & Frontend Integration

V2 is event-driven.

Backend must:

- Listen to `ProjectCreated`
- Store module addresses per project
- Dynamically instantiate contracts

Frontend must:

- Never hardcode project module addresses
- Fetch them from backend
- Use BigInt for all monetary values

---

# Disclaimer

This deployment is currently on Celo Sepolia testnet.

Mainnet deployment will require:

- Final security review
- Permission verification
- Economic simulation validation
- Multisig administration setup

Use at your own risk.

---

# Versioning

- MVP V1: Frozen (monolithic)
- MVP V2: Modular architecture
- Future versions will follow semantic versioning

---
