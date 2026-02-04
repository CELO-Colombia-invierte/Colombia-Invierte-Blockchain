# 🏗️ Platform Contracts — MVP V1

Smart contracts for a simple on-chain platform that deploys:

- **Natillera** (savings pool)
- **Tokenizacion** (fixed-price token sale)

Using a **factory pattern** (`Platform`) with **EIP-1167 minimal proxies** for gas-efficient deployments.

---

## 📦 Tech Stack

- Solidity `^0.8.30`
- Foundry
- OpenZeppelin
- Celo (Alfajores Testnet)

---

## 🧱 Architecture Overview

Platform (Factory)
│
├── Natillera (implementation)
│ └── cloned per project
│
└── Tokenizacion (implementation)
└── cloned per project

### Key Design Decisions

- **Factory + Clones (EIP-1167)**  
  Cheap deployments, upgradeable at the factory level.
- **MVP V1 scope**
  - No user registry
  - No upgrade proxies per project
  - Fixed deployment fee
- **Creator-based permissions**
  - Each project has a `creator`
  - Platform is only responsible for deployment

---

## 🧠 Contracts

### Platform.sol

Factory contract that:

- Deploys Natillera & Tokenizacion clones
- Collects a fixed ETH deployment fee
- Tracks projects by incremental `projectId`

Main functions:

- `deployNatillera(...)`
- `deployTokenizacion(...)`
- `updateFee(...)`
- `updateImplementation(...)`

---

### Natillera.sol

Savings pool contract (MVP V1):

- Fixed contribution cycles
- Cycle-based accounting
- Manual or automatic finalization (anti-funds-locking)

---

### Tokenizacion.sol

Fixed-price token sale:

- ERC20 or native ETH payments
- Time-based sale window
- Manual finalization
- Creator withdraws collected funds

---

## 🧪 Tests

Run all tests:

```bash
forge test

Covered in MVP V1:

    Deployment & initialization

    Basic happy paths

    Time-based restrictions

    Minimal revert conditions

    Note: Edge cases and stress tests are intentionally deferred to later phases.

🚀 Deployment (Celo Alfajores)
Environment variables

export PRIVATE_KEY=0xYOUR_PRIVATE_KEY
export RPC_URL=https://alfajores-forno.celo-testnet.org

Deploy script

forge script script/Deploy.s.sol:DeployAlfajores \
  --rpc-url $RPC_URL \
  --broadcast

Contracts deployed:

    Natillera (implementation)

    Tokenizacion (implementation)

    Platform (factory)

📤 Post-Deploy Checklist

    Export ABIs (out/*.json)

    Backend:

        Install dependencies

        Create services to interact with Platform

    Frontend:

        Consume Platform events

        Instantiate projects

    Document deployed addresses

⚠️ MVP V1 Limitations

    No upgradeability per project

    No emergency pause

    No role system

    No treasury split

These are explicit design choices for MVP V1.
🛣️ Roadmap

    MVP 1.5: Hardening + extra tests

    MVP 2: Roles, registry, pausability

    Audit & Mainnet

Built with ❤️ and gas awareness.
```
