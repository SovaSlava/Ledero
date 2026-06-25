# 📖 Ledero Documentation

This document provides a deep technical dive into the Ledero protocol architecture, execution flows, and security measures.

---

## Table of Contents

1. [System Architecture Overview](#1-system-architecture-overview)
2. [Repository Structure & Core Components](#2-repository-structure--core-components)
3. [Execution Flows (Under the Hood)](#3-execution-flows-under-the-hood)
4. [Technical Innovations & Gas Optimizations](#4-technical-innovations--gas-optimizations)
5. [Math & Risk Management](#5-math--risk-management)
6. [Security & Invariant Testing](#6-security--invariant-testing)
7. [Developer & Integrator Guide](#7-developer--integrator-guide)

---

## 1. System Architecture Overview

### High-Level Design

Ledero follows a **hub-and-spoke** architecture. The **Core Engine** (`Ledero.sol`) acts as the central orchestrator, while protocol-specific logic is abstracted into **Stateless Adapters**. This separation ensures that the core logic remains lean and agnostic to the underlying lending or swap protocols.

### The Beacon Proxy Pattern

The **Core Engine** is deployed using the **Beacon Proxy** pattern. This choice provides several advantages:

- **Synchronized Upgrades**: A single update to the Beacon contract immediately upgrades the logic for all associated proxies.
- **Isolation**: It is important to note that **only the Ledero Core engine resides behind a proxy**. All Adapters (Lending, Flash Loan, Swap) are deployed as standalone, immutable contracts to minimize complexity and maximize trust.

---

## 2. Repository Structure & Core Components

### Repository Tree

The codebase is strictly organized to separate core logic, external adapters, and testing infrastructure:

```text
ledero/
├── src/
│   ├── base/                       # Core execution and context modules
│   │   ├── ActionExecutor.sol      # Engine for processing AdapterAction arrays safely
│   │   └── TransientContext.sol    # EIP-1153 context packing (expected caller & operation)
│   ├── adapters/                   # Protocol-specific stateless adapters
│   │   ├── lendings/               # Aave V3, Compound V3 adapters
│   │   ├── loan/                   # Balancer V3 flash loan adapter
│   │   └── swap/                   # 1inch swap adapter
│   ├── interfaces/                 # Internal and external shared interfaces
│   ├── libraries/                  # Shared core libraries
│   │   ├── LeverageMath.sol        # Complex leverage and health factor calculations
│   ├── Ledero.sol                  # Core engine (Beacon Proxy implementation)
│   ├── LederoOracle.sol            # Chainlink price feed registry
│   └── LederoQuoter.sol            # Off-chain calculation helper
├── test/
│   ├── base/                       # Base test setup and fixtures
│   ├── mock/                       # Mock contracts for isolated unit testing
│   ├── unit/                       # Isolated unit tests for core components
│   ├── fork/                       # Mainnet fork testing
│   │   └── Ledero.t.sol            # Live liquidity and integration tests
│   └── fuzzing/                    # Stateless fuzzing
│       └── LeverageMath.t.sol      # Math library fuzzing

└── script/
    ├── DeployLedero.s.sol          # Main deployment and verification script
    ├── UpgradeLedero.s.sol         # Beacon proxy logic upgrade script
    └── CalculateAddress.ts         # FFI script for vanity address generation
```

### Core Execution Modules

- ActionExecutor.sol: A low-level execution engine that safely processes the AdapterAction arrays returned by adapters. It centralizes error handling, prevents reentrancy issues related to malformed targets, and manages token approvals dynamically.

- TransientContext.sol: A highly optimized module utilizing EIP-1153 transient storage (TSTORE/TLOAD) to pack the expected flashloan callback address and the current operation type into a single storage slot.

### Core Libraries

- **`TransientBytes.sol`**: A highly optimized library utilizing inline `assembly` to pack and unpack execution parameters directly into EIP-1153 transient storage. This ensures secure, gas-efficient context passing during flash loan callbacks.
- **`LeverageMath.sol`**: Encapsulates the mathematical logic required to calculate flash loan sizes, expected debt, and safe collateralization ratios.

### `Ledero.sol` (Core Engine)

The main entry point for all user operations. It orchestrates the flow by requesting actions from adapters and passing them to the ActionExecutor.

Architecture Note: For enhanced security and state isolation, each deployed instance of the Ledero contract is designed to manage exactly one active position.

### `LederoQuoter.sol` (Off-chain Helper)

A read-only utility contract designed for front-end integration. **It is mandatory to query this contract before executing any leveraged transactions**.

- **Calculations**: Provides exact parameters (`flashLoanAmount`, `borrowAmount`, `collateralToWithdraw`) required by `Ledero.sol` functions.
- **Slippage Estimation**: Helps users set realistic `minReturnAmount` values for swaps.

### `LederoOracle.sol` (Price Registry)

The source of truth for asset pricing, integrating directly with **Chainlink Price Feeds**.

- **Admin Setup**: The protocol owner must manually configure price feeds and heartbeat limits for each supported token via `setPriceFeed()` before the quoter and core contracts can operate.
- **Safety Checks**: Validates prices against `heartbeat` thresholds (staleness checks).

---

## 3. Execution Flows (Under the Hood)

(Preparation and Lifecycle phases remain identical, but internally they rely on executing AdapterAction[] arrays requested from adapters).

### Preparation Phase (Quoter & Oracle)

Before any position is opened or closed, the frontend must interact with the peripheral contracts:

1. **Oracle Check**: Ensure `LederoOracle` has active and fresh Chainlink price feeds configured.
2. **Quote Generation**: The user calls `calculateOpenParams` or `calculateUnwindParams` on `LederoQuoter`.

### Open Position Lifecycle

1. **User Call**: User invokes `createLeveragedPosition()` passing the necessary parameters and the swap payload.
2. **Context Setup**: Core stores `Operation.OPEN_POSITION` and the expected adapter addresses in transient storage using `TransientContext`.
3. **Flash Loan Initiation**: Core requests the initial `AdapterAction[]` from the Flash Loan Adapter and processes it via the `ActionExecutor` to trigger a flash loan in the Collateral Token.
4. **The Callback**: The external flash loan provider calls back into Ledero's `receiveFlashLoan()`.
5. **Atomic Execution**: Inside the callback, the Core sequentially orchestrates the following:
   - **Supply & Borrow**: Core requests the `AdapterAction[]` from the Lending Adapter and executes it to supply both the user's margin and the flash loan funds into the pool, and then borrow the Debt tokens.
   - **Swap**: Core requests the `AdapterAction[]` from the Swap Adapter and executes it to swap the borrowed Debt tokens via 1inch back into Collateral tokens.
   - **Repay**: Core requests the repay `AdapterAction[]` from the Flash Loan Adapter and executes it to return the funds to the provider.
   - **Reinvest**: Any remaining swap "dust" is supplied back into the lending pool to maximize the Health Factor.

### Unwind Position Lifecycle

1. **User Call**: User invokes `unwindPosition()` passing the necessary parameters and the swap payload.
2. **Context Setup**: Core stores `Operation.UNWIND_POSITION` and the relevant adapter addresses in transient storage.
3. **Flash Loan Initiation**: Core requests the initial `AdapterAction[]` from the Flash Loan Adapter and processes it via the `ActionExecutor` to trigger a flash loan in the **Debt Token** (e.g., USDC) to cover the outstanding debt.
4. **The Callback**: The external flash loan provider calls back into Ledero's `receiveFlashLoan()`.
5. **Atomic Execution**: Inside the callback, the Core sequentially orchestrates the following:
   - **Repay & Withdraw**: Core requests the `AdapterAction[]` from the Lending Adapter and executes it to completely repay the debt in the lending pool and withdraw the unlocked collateral to the Ledero contract.
   - **Swap**: Core requests the `AdapterAction[]` from the Swap Adapter and executes it to swap just enough collateral into the Debt Token to cover the flash loan repayment.
   - **Repay Flash Loan**: Core requests the repay `AdapterAction[]` from the Flash Loan Adapter and executes it to return the Debt tokens to the provider.
   - **Profit Distribution**: The Core contract directly transfers the remaining Collateral tokens (net profit) to the user's wallet.
   - **Safety Check**: If the position is only partially unwound, a final Health Factor check ensures the remaining position is safe from liquidation.

### Migrate Position Lifecycle

1. **User Call**: User invokes `migratePosition()` passing the exact balances to move, along with the source and destination lending adapter addresses.
2. **Context Setup**: Core stores `Operation.MIGRATE_POSITION` and the relevant adapter addresses (flash loan, source lending, destination lending) in transient storage.
3. **Flash Loan Initiation**: Core requests the initial `AdapterAction[]` from the Flash Loan Adapter and processes it via the `ActionExecutor` to trigger a flash loan in the **Debt Token** equal to the user's total outstanding debt in the original protocol.
4. **The Callback**: The external flash loan provider calls back into Ledero's `receiveFlashLoan()`.
5. **Atomic Execution**: Inside the callback, the Core sequentially orchestrates the following:
   - **Repay & Withdraw (Source)**: Core requests the `AdapterAction[]` from the **Source** Lending Adapter and executes it to repay the debt and withdraw all collateral from the original pool (e.g., Aave).
   - **Supply & Borrow (Destination)**: Core requests the `AdapterAction[]` from the **Destination** Lending Adapter and executes it to supply the withdrawn collateral into the new pool (e.g., Compound V3) and borrow the exact amount of Debt Tokens needed to cover the flash loan.
   - **Repay Flash Loan**: Core requests the repay `AdapterAction[]` from the Flash Loan Adapter and executes it to return the newly borrowed Debt Tokens to the provider.
   - **Seamless Transition**: The transaction finalizes, leaving the user with the exact same leveraged exposure in the new protocol — entirely achieved through declarative actions and the `ActionExecutor` without requiring upfront capital.

## 4. Technical Innovations & Gas Optimizations

Ledero is built to be highly gas-efficient and EVM-native, utilizing Solidity `0.8.35` features to bypass legacy architectural limitations.

### Transient Context Passing (EIP-1153)

Ledero utilizes **Transient Storage (`TSTORE`/`TLOAD`)** combined with assembly packing in one slot address of expected caller flashloan callback function and current type of operation.

The state is automatically cleared at the end of the transaction, costing only 100 gas and fundamentally eliminating reentrancy attack vectors.

### Vanity Adapter Addresses

To prevent accidental user errors, CREATE2 is used with strict prefix verification. Valid adapter addresses **must start with 0x0000** followed by a specific hex prefix:

- Prefix `1`: Lending Adapters
- Prefix `2`: Flash Loan Adapters
- Prefix `3`: Swap Adapters

---

## 5. Math & Risk Management

### Slippage & MEV Protection

1. `LederoQuoter` calculates the exact `totalFlashRepay` amount.
2. This is passed as `minReturnAmount`.
3. If the swap returns less than required to repay the flash loan + fees, the transaction reverts.

### Health Factor (HF) Protection

After the core loop, any "dust" is automatically supplied back into the lending protocol. The system then verifies that the final Health Factor is within a safe range to prevent immediate liquidation.

---

## 6. Security & Invariant Testing

### Advanced Testing

- Deep Unit Testing: Extensive use of localized Foundry Mocks to simulate low-level EVM failures, missing returnData, zero-address targets, and extreme "dust" scenarios.

- Mainnet Fork: Integration tests run against a live Ethereum Mainnet fork to verify correct ABI encoding and real liquidity interactions.

- Fuzzing: Implements stateless Fuzzing (via vm.assume and bound) to ensure mathematical boundaries within LeverageMath and system stability.

---

## 7. Developer & Integrator Guide

### Environment Setup & Deployment

Before deploying or running live tests, you must configure your environment variables.

1. Rename the example environment file:
   ```bash
   cp env.example .env
   ```
2. Fill in the required variables in `.env` (RPC URLs, private keys, etc.).
   - _Note: You can obtain a free 1inch API key by registering at [business.1inch.com](https://business.1inch.com/)._

3. Install dependencies

   ```bash
   forge install
   npm i
   ```

4. To deploy the Ledero core engine and all adapters, run the following script:
   ```bash
   forge script script/DeployLedero.s.sol --rpc-url $ETH_RPC_URL --broadcast --verify --ffi -vv
   ```

### Running the Test Suite

The project uses Foundry and relies on Ethereum Mainnet forks to test against real protocol states and liquidity.

```bash
# Run fork tests
forge test --mp test/fork/Ledero.t.sol --fork-url $ETH_RPC_URL
# Run unit tests
forge test --match-path "test/unit/*"
# Run fuzzing tests
forge test --mp test/fuzzing/LeverageMath.t.sol
# Coverage
forge coverage --match-path "test/{unit,fork}/**" --fork-url $ETH_RPC_URL
```
