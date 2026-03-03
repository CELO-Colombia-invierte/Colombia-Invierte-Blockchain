> ⚠️ **Status: MVP V1 — Legacy / Stable**
>
> This version represents the **first functional MVP** of the platform.
> It is **feature-complete for V1**, deployed on testnet, and currently being
> integrated with backend and frontend.
>
> 🔒 **Frozen scope**
>
> - No new features will be added.
> - Only critical bug fixes or security patches are allowed.
>
> 🧭 **Next iteration**
>
> - Active development continues on **MVP V2** under the `release/mvp-v2` branch.
> - MVP V2 introduces a redesigned architecture (custody phases, governance, vaults).
>
> If you are starting new development, **do not build on top of V1**.

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
- Celo (Sepolia Testnet)

---

## 🧱 Architecture Overview

```
Platform (Factory)
│
├── Natillera (implementation)
│   └── cloned per project
│
└── Tokenizacion (implementation)
    └── cloned per project
```

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

## 📍 Deployed Addresses (Celo Sepolia)

All contracts are verified on [Celoscan](https://sepolia.celoscan.io).

### Implementations

- **Natillera Implementation**: `0x86512228C805dDa61CE8Fd206e102f2D3896eC32`
- **Tokenizacion Implementation**: `0x4aC6D7F58Dba458eA74179c826378B5ba5fB3179`

### Platform (Factory)

- **Platform**: `0xbe919DccE1218E2C5e17dc3409aEb3EF38f049A4`

---

## 🌐 Supported Networks

| Network      | Status    | Chain ID | Currency |
| ------------ | --------- | -------- | -------- |
| Celo Sepolia | ✅ Active | 11142220 | CELO     |

**RPC**: `https://forno.celo-sepolia.celo-testnet.org`  
**Block Explorer**: `https://sepolia.celoscan.io`

---

## 🧠 Contracts

### Platform.sol

Factory contract that:

- Deploys Natillera & Tokenizacion clones
- Collects a fixed ETH deployment fee
- Tracks projects by incremental `projectId`

**Main functions:**

- `deployNatillera(...)`
- `deployTokenizacion(...)`
- `updateFee(...)`
- `updateImplementation(...)`

### Natillera.sol

Savings pool contract (MVP V1):

- Fixed contribution cycles
- Cycle-based accounting
- Manual or automatic finalization (anti-funds-locking)

### Tokenizacion.sol

Fixed-price token sale:

- ERC20 or native ETH payments
- Time-based sale window
- Manual finalization
- Creator withdraws collected funds

---

## 🧪 Testing

Run all tests:

```bash
forge test
```

**Covered in MVP V1:**

- Deployment & initialization
- Basic happy paths
- Time-based restrictions
- Minimal revert conditions

_Note: Edge cases and stress tests are intentionally deferred to later phases._

---

## 🚀 Deployment

### Environment Variables

```bash
export PRIVATE_KEY=0xYOUR_PRIVATE_KEY
export RPC_URL=https://forno.celo-sepolia.celo-testnet.org
```

### Deploy Script

```bash
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --slow
```

### Verification

Contracts are automatically verified using Foundry. Requirements:

- Correct RPC (Celo Sepolia)
- Sufficient CELO balance
- `PRIVATE_KEY` configured

---

## 📤 Post-Deploy Checklist

1. **Export ABIs** (`out/*.json`)
2. **Backend:**
   - Install dependencies
   - Create services to interact with Platform
3. **Frontend:**
   - Consume Platform events
   - Instantiate projects
4. **Document deployed addresses**

---

## ⚠️ MVP V1 Limitations

- No upgradeability per project
- No emergency pause
- No role system
- No treasury split

_These are explicit design choices for MVP V1._

---

## 🛣️ Roadmap

- **MVP 1.5:** Hardening + extra tests
- **MVP 2:** Roles, registry, pausability
- **Audit & Mainnet**

---

Built with ❤️ and gas awareness.
