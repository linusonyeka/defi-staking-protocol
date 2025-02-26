# DeFi Staking Protocol

## Overview
The **DeFi Staking Protocol** is a smart contract implemented in Clarity that enables **liquidity pooling** and **yield farming** with optimized staking mechanics. Users can deposit fungible tokens into the protocol, earn liquidity shares, and withdraw with accumulated yield rewards. The contract is designed with security checks, time locks, and an administrative governance model.

## Features
- **Liquidity Pooling**: Users can provide liquidity by depositing base and quote tokens.
- **Yield Farming**: Users earn rewards based on the yield rate and staking duration.
- **Minimum Deposit Enforcement**: Prevents dust attacks with a minimum staking requirement.
- **Time-Locked Staking**: Users must wait a specified period before withdrawing.
- **Fee Mechanism**: A swap fee applies to trades in the protocol.
- **Governance Controls**: Admin role management and adjustable yield rates.

## Smart Contract Components

### Fungible Token Trait
Defines the required token interface for supported tokens:
- `transfer`
- `get-name`
- `get-symbol`
- `get-decimals`
- `get-balance`
- `get-total-supply`

### Constants & Errors
- **Minimum Deposit Amount**: `u100000`
- **Staking Period**: `u144` (~24 hours in blocks)
- **Base Yield Rate**: `u100` (1.00x yield multiplier)
- **Error Codes**: Ensures proper validation, including unauthorized access, insufficient funds, token mismatches, etc.

### Core Functions

#### Public Functions
- `deposit-liquidity`: Deposits base and quote tokens into the liquidity pool.
- `withdraw-liquidity`: Withdraws staked tokens after the staking period.
- `transfer-admin`: Transfers admin rights to another verified user.
- `update-yield-rate`: Updates the staking reward rate.
- `set-protocol-status`: Enables or disables the protocol.

#### Read-Only Functions
- `get-staker-position`: Retrieves staking details for a given user.
- `get-pool-data`: Retrieves liquidity pool details.
- `calculate-share-issuance`: Calculates liquidity share issuance based on token amounts.

#### Private Helper Functions
- `min-uint`: Returns the smaller of two `uint` values.
- `update-pool-state`: Updates the internal liquidity pool reserves.
- `calculate-yield`: Computes staking rewards based on the staked duration and yield rate.
- `verify-and-update-admin`: Validates and assigns a new admin.

## Deployment & Usage

### Prerequisites
- Stacks blockchain wallet
- Clarity contract deployment tools

### Steps to Deploy
1. Compile the contract.
2. Deploy the contract to the Stacks blockchain.
3. Register supported fungible tokens by implementing `ft-trait`.
4. Initialize admin rights.

### Interacting with the Contract
Users can interact with the contract via Clarity smart contract calls using the provided functions. Ensure that:
- The deposited amount meets the minimum threshold.
- The tokens used match the expected contract addresses.
- Withdrawals are made after the unlock period.

## Contribution & Development

### Pull Request Guidelines
If you would like to contribute, please follow these steps:
1. Fork the repository.
2. Create a new branch for your changes.
3. Make the necessary changes and test them.
4. Submit a pull request with a descriptive title and explanation of changes.

