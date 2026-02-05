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

- **Natillera Implementation**: `0x3d18dBb583c0DaEfeD73882DFb0CF74A49C4c482`
- **Tokenizacion Implementation**: `0x8a2c0F81a7B281b24f55f36569887993f5955D6A`

### Platform (Factory)

- **Platform**: `0x151aD264F58204267d23814B220514182aA4C56a`

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
