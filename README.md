
# TapprWallet Smart Contract

A secure Sui Move–based custodial wallet module with Verilens TEE-powered attestation, anti-replay protection, daily limits, platform fee management, and on-chain proof generation. This contract is used within the **Tappr Fintech payment infrastructure** to ensure cryptographically verifiable, fraud-resistant transactions.

## Features

### 🔐 Wallet Management
- Create non-custodial on-chain wallets tied to a Sui address  
- Freeze / unfreeze enforcement  
- KYC verification state tracking  
- Balance lookups and statistics

### 🧾 Verilens Attestation Integration
The contract integrates with **Verilens TEE (Trusted Execution Environment)** for:
- Transaction validation  
- Signature verification  
- Fraud detection  
- Business rule enforcement  
- User authorization  

On-chain logic **only checks nonce replay**, trusting Verilens for deeper verification.

### 🔁 Anti-Replay Protection
A `VerilensAttestationRegistry` tracks all used nonces.  
Any reused attestation is rejected (`E_ATTESTATION_ALREADY_USED`).

### 💰 Fees & Limits
- Platform fee: **0.5% (50 BPS)**  
- Minimum transfer: **0.001 SUI**  
- Daily spending limit  
- Per-transaction limit  
- Fee vault collects platform revenue

### 🧾 On-Chain Transaction Proofs
Every withdrawal and transfer generates a `VerifiedTransaction` object containing:
- transaction hash  
- full TEE attestation  
- timestamp  
- wallet address  
- amount  

Events emitted notify Web2 backend for DB synchronization.

### 📡 Events Emitted
- `WalletCreatedEvent`
- `DepositEvent`
- `WithdrawalEvent`
- `TransferEvent`
- `TransactionVerifiedOnChainEvent`
- Many others for admin and analytics usage

Events enable:
- backend synchronization  
- analytics  
- fraud monitoring  
- audit trails  

## Entry Functions

### `create_wallet(ctx)`
Creates a new Sui-based wallet with default limits.

### `deposit_with_attestation(...)`
Deposits SUI into a wallet using Verilens attestation to validate the off-chain source.

### `withdraw_with_attestation(...)`
Withdraws SUI to another address with:
- fee deduction  
- limit checks  
- creation of on-chain proof  
- Verilens anti-replay enforcement  

### `transfer_with_attestation(...)`
Moves SUI between TapprWallets with:
- half-fee model  
- replay protection  
- proof generation  

## Important Constants
| Constant | Value | Description |
|---------|--------|-------------|
| `MINIMUM_TRANSACTION` | 0.001 SUI | Smallest allowable movement |
| `DEFAULT_DAILY_LIMIT` | 10 SUI | Max daily spend |
| `DEFAULT_TRANSACTION_LIMIT` | 5 SUI | Max per-transaction |
| `PLATFORM_FEE_BPS` | 50 BPS | 0.5% fee |

## Security Model

### ✔ Verilens-TEE Verified Input
Move contract does not redo signature validation and business rule checks.  
The Verilens TEE:
- validates signatures  
- checks rules  
- detects fraud  
- signs attestation  

### ✔ Move Contract Guarantees
- anti-replay via nonce tracking  
- balance and limit enforcement  
- fee collection correctness  
- on-chain state creation  

### ✔ Combined Trust Model
TEE + Move ensures:
- strong off-chain verification  
- strong on-chain enforcement  

## Deployment Notes
- Run `init()` automatically upon publishing  
- `AdminCap` transferred to publisher  
- `FeeVault` and `AttestationRegistry` become shared objects  

## License
Tapr is a proprietary project. Tappr uses the following open-source components:

Walrus SDK — Copyright (c) Mysten Labs. Licensed under Apache-2.0.
Nautilus Templates — Copyright (c) Mysten Labs Licensed under the Apache 2.0.

---



