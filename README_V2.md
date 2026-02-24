# 🧠 Platform Contracts — MVP V2 (In Progress)

> **Status:** In active development  
> **Branch:** `release/mvp-v2`

MVP V2 is the next iteration of the Colombia Invierte smart contracts,
built on top of the lessons learned from MVP V1.

This version **does not refactor or replace MVP V1**.
Both versions are expected to coexist during development and evaluation.

MVP V2 evolves the architecture to support real-world constraints
while keeping complexity, risk, and cognitive load under control.

---

## 🎯 Goals of MVP V2

- Introduce **custody by phases** (vault-based fund release)
- Add **minimal governance** (approvals, disputes, emergency actions)
- Support **stablecoin-first flows** (USD-pegged and local-pegged)
- Maintain **auditability and composability**
- Deliver a **clear, defensible buildathon demo**

---

## 🧠 Guiding Principles (Non-Negotiable)

- MVP V1 remains **frozen and untouched**
- No user funds without **explicit custody and control**
- **No monolithic contracts**
  - Prefer small, composable modules
  - Avoid contracts >300–400 LOC unless strictly justified
- Clarity over cleverness
- Features must be implemented **strictly by phase**

---

## 🪙 Stablecoin-First (Flexible)

MVP V2 is designed around stablecoin usage:

- USD-pegged (USDC / USDT / cUSD)
- Local-currency-pegged (e.g. COP stablecoins), when available

Stablecoin-first does **not** mean USD-only.

---

## 🗂️ Repository Structure (V2)

Contracts, interfaces, tests, mocks and ABIs are **explicitly versioned**:

```text
src/
├── contracts/
│   ├── v1/        # Legacy (frozen)
│   └── v2/        # Active development
│
├── interfaces/
│   ├── v1/
│   ├── v2/
│   └── shared/
│
└── tests/
    ├── v1/
    └── v2/

⚠️ Disclaimer

MVP V2 is not deployed, not audited, and not production-ready.

APIs, storage layout, and behavior may change until the scope
and phases are fully completed.
```
