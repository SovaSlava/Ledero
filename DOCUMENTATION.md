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
* **Synchronized Upgrades**: A single update to the Beacon contract immediately upgrades the logic for all associated proxies.
* **Isolation**: It is important to note that **only the Ledero Core engine resides behind a proxy**. All Adapters (Lending, Flash Loan, Swap) are deployed as standalone, immutable contracts to minimize complexity and maximize trust.

---

## 2. Repository Structure & Core Components

### Repository Tree
The codebase is strictly organized to separate core logic, external adapters, and testing infrastructure:

```text
ledero/
├── src/
│   ├── adapters/                   # Protocol-specific stateless adapters
│   │   ├── lendings/               # Aave V3, Compound V3 adapters
│   │   ├── loan/                   # Balancer V3 flash loan adapter
│   │   └── swap/                   # 1inch swap adapter
│   ├── interfaces/                 # Internal and external shared interfaces
│   ├── libraries/                  # Shared core libraries
│   │   ├── LeverageMath.sol        # Complex leverage and health factor calculations
│   │   └── TransientBytes.sol      # Assembly-optimized transient storage packing
│   ├── Ledero.sol                  # Core engine (Beacon Proxy implementation)
│   ├── LederoOracle.sol            # Chainlink price feed registry
│   └── LederoQuoter.sol            # Off-chain calculation helper
├── test/
│   ├── base/                       # Base test setup and fixtures
│   ├── mock/                       # Mock contracts for isolated unit testing
│   ├── unit/                       # Isolated unit tests for core components
│   ├── fork/                       # Mainnet fork testing
│   │   └── Ledero.t.sol            # Live liquidity and integration tests
│   ├── fuzzing/                    # Stateless fuzzing
│   │   └── LeverageMath.t.sol      # Math library fuzzing
│   └── invariants/                 # Stateful fuzzing
│       ├── LederoInvariants.t.sol  # Core invariant assertions
│       └── LederoHandler.t.sol     # Fuzzing handler for state transitions
└── script/
    ├── DeployLedero.s.sol          # Main deployment and verification script
    ├── UpgradeLedero.s.sol         # Beacon proxy logic upgrade script
    └── CalculateAddress.ts         # FFI script for vanity address generation
```

### Core Libraries
* **`TransientBytes.sol`**: A highly optimized library utilizing inline `assembly` to pack and unpack execution parameters directly into EIP-1153 transient storage. This ensures secure, gas-efficient context passing during flash loan callbacks.
* **`LeverageMath.sol`**: Encapsulates the mathematical logic required to calculate flash loan sizes, expected debt, and safe collateralization ratios.

### `Ledero.sol` (Core Engine)
The main entry point for all user operations. It manages the execution state, validates adapter calls, and handles the atomic flow of funds. 
* **State Management**: Uses transient storage to maintain context during flash loan callbacks.
* **Architecture Note**: For enhanced security and state isolation, each deployed instance of the Ledero contract is designed to manage exactly one active position.

### `LederoQuoter.sol` (Off-chain Helper)
A read-only utility contract designed for front-end integration. **It is mandatory to query this contract before executing any leveraged transactions**.
* **Calculations**: Provides exact parameters (`flashLoanAmount`, `borrowAmount`, `collateralToWithdraw`) required by `Ledero.sol` functions.
* **Slippage Estimation**: Helps users set realistic `minReturnAmount` values for swaps.

### `LederoOracle.sol` (Price Registry)
The source of truth for asset pricing, integrating directly with **Chainlink Price Feeds**.
* **Admin Setup**: The protocol owner must manually configure price feeds and heartbeat limits for each supported token via `setPriceFeed()` before the quoter and core contracts can operate.
* **Safety Checks**: Validates prices against `heartbeat` thresholds (staleness checks).

---

## 3. Execution Flows (Under the Hood)

### Preparation Phase (Quoter & Oracle)
Before any position is opened or closed, the frontend must interact with the peripheral contracts:
1. **Oracle Check**: Ensure `LederoOracle` has active and fresh Chainlink price feeds configured.
2. **Quote Generation**: The user calls `calculateOpenParams` or `calculateUnwindParams` on `LederoQuoter`.

### Open Position Lifecycle
1. **User Call**: User invokes `createLeveragedPosition()` passing the parameters from `LederoQuoter` and the swap payload.
2. **Context Setup**: Core stores `Operation.OPEN_POSITION` and expected adapter addresses in transient storage.
3. **Flash Loan Initiation**: Core requests a flash loan in the Collateral Token from the Flash Loan adapter (e.g., Balancer).
4. **The Callback**: The external protocol calls back to Ledero's `receiveFlashLoan()`.
5. **Atomic Execution**:
    * **Supply & Borrow**: Margin + Flash Loan funds are sent to the Lending Adapter, and Debt tokens are borrowed from the pool.
    * **Swap**: Debt tokens are swapped via the Swap Adapter (1inch) back into collateral tokens.
    * **Repay**: The flash loan is repaid using the swapped tokens.
    * **Reinvest**: Any swap "dust" is supplied back into the pool to maximize the Health Factor.

### Unwind Position Lifecycle
1. **User Call**: User invokes `unwindPosition()` passing parameters from `LederoQuoter` and the swap payload.
2. **Context Setup**: Core stores `Operation.UNWIND_POSITION` and the flash adapter address in transient storage.
3. **Flash Loan Initiation**: Core requests a flash loan in the **Debt Token** (e.g., WETH) to cover the user's outstanding debt.
4. **The Callback**: The provider calls back to Ledero's `receiveFlashLoan()`.
5. **Atomic Execution**:
    * **Repay & Withdraw**: Flash loan funds repay the debt in the Lending pool. Collateral is withdrawn to the Ledero contract.
    * **Swap**: A portion of collateral is swapped via 1inch back into the Debt Token to cover the flash loan.
    * **Repay Flash Loan**: The swapped debt tokens are returned to the flash loan provider.
    * **Profit Distribution**: Remaining tokens are transferred directly to the user's wallet.
    * **Safety Check**: If not closed entirely, a Health Factor check ensures the remaining position is safe.

---

## 4. Technical Innovations & Gas Optimizations

Ledero is built to be highly gas-efficient and EVM-native, utilizing Solidity `0.8.35` features to bypass legacy architectural limitations.

### Transient Context Passing (EIP-1153)
Ledero utilizes **Transient Storage (`TSTORE`/`TLOAD`)** combined with assembly packing:
```solidity
address transient _expectedFlashAdapter;
Operation transient _currentOperation;
```
The state is automatically cleared at the end of the transaction, costing only 100 gas and fundamentally eliminating reentrancy attack vectors.

### Vanity Adapter Addresses ($O(1)$ Validation)
To prevent accidental user errors, CREATE2 is used with strict prefix verification. Valid adapter addresses **must start with 0x0000** followed by a specific hex prefix:
* Prefix `1`: Lending Adapters
* Prefix `2`: Flash Loan Adapters
* Prefix `3`: Swap Adapters

### Delegatecall for Lending Adapters
Lending adapters are invoked using `delegatecall`. This allows the Core Engine to interact with lending pools while retaining the `msg.sender` context and holding the collateral directly on the `Ledero` proxy.

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

Ledero is built with a strong focus on formal verification and property-based testing.

### Key Invariants Formally Verified
* **System Dust is Strictly Zero**: Neither the core nor adapters ever trap tokens.
* **Guaranteed Solvency**: Health Factor in Aave or Compound never drops below `MIN_SAFE_HF`.
* **Absolute Debt Clearance**: Closing an operation entirely results in 0 remaining debt in the external protocol.

---

## 7. Developer & Integrator Guide

### Environment Setup & Deployment
Before deploying or running live tests, you must configure your environment variables.

1. Rename the example environment file:
   ```bash
   cp env.example .env
   ```
2. Fill in the required variables in `.env` (RPC URLs, private keys, etc.).
   * *Note: You can obtain a free 1inch API key by registering at [business.1inch.com](https://business.1inch.com/).*

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
forge test --mp test/fork/Ledero.t.sol --rpc-url $ETH_RPC_URL 
```