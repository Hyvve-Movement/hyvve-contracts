# Hyvve Data Marketplace - Smart Contracts

A decentralized marketplace for data collection and contribution built on the Aptos blockchain.

## Overview

Hyvve Data Marketplace is a platform that enables organizations to create data collection campaigns and incentivize contributors to submit high-quality data. The platform uses smart contracts to manage campaigns, contributions, escrow funds, and reputation.

## Project Structure

```
├── sources/                # Move smart contracts
│   ├── campaign_manager.move      # Campaign creation and management
│   ├── campaign_state.move        # Campaign state tracking
│   ├── contribution_manager.move  # Contribution submission and verification
│   ├── escrow_manager.move        # Funds management and reward distribution
│   ├── reputation.move            # Contributor reputation system
│   ├── subscription.move          # Subscription management
│   └── verifier.move              # Data verification logic
├── scripts/                # TypeScript CLI tools
│   ├── cli/                # Command-line interface scripts
│   │   ├── campaign/       # Campaign management commands
│   │   ├── contribution/   # Contribution submission commands
│   │   ├── profile/        # User profile management
│   │   ├── reputation/     # Reputation management
│   │   ├── stats/          # Statistics and reporting
│   │   └── verifier/       # Verification tools
│   ├── config/             # Configuration files
│   ├── setup/              # Setup and initialization scripts
│   └── utils/              # Utility functions
└── Move.toml               # Move package configuration
```

## Smart Contracts

### Campaign Manager

Handles the creation, management, and lifecycle of data collection campaigns. Campaign creators can define requirements, set budgets, and specify reward structures.

### Contribution Manager

Manages the submission and verification of data contributions. Contributors can submit data to active campaigns and receive rewards based on quality.

### Escrow Manager

Secures funds for campaigns and handles the distribution of rewards. Implements a secure escrow system with platform fees and automatic reward distribution.

### Reputation System

Tracks contributor reputation based on the quality and quantity of their contributions. Higher reputation can lead to better opportunities and rewards.

### Verifier

Implements verification logic to ensure data quality. Supports various verification methods and quality scoring.

## CLI Commands

Hyvve Data Marketplace provides a centralized CLI tool for interacting with the smart contracts.

### Installation

To install the CLI globally:

```bash
# Navigate to the project directory
cd hyvve-contracts

# Install dependencies
npm install

# Install the CLI globally
node scripts/setup/install-cli.js
```

### Usage

Once installed, you can use the CLI with the following syntax:

```bash
hyvve-cli <category> <command>
```

For example:

```bash
hyvve-cli campaign create_campaign
hyvve-cli contribution submit_contribution
```

To see all available commands:

```bash
hyvve-cli --help
```

For more detailed information about the CLI, see the [CLI documentation](scripts/README.md) and the [CLI Cheat Sheet](scripts/CHEATSHEET.md).

### Campaign Management

- `campaign create_campaign` - Create a new data collection campaign
- `campaign list_active_campaigns` - List all active campaigns
- `campaign get_campaign_pubkey` - Get the public key for a campaign
- `campaign get_remaining_budget` - Check the remaining budget for a campaign

### Contribution Management

- `contribution submit_contribution` - Submit a new data contribution to a campaign
- `contribution get_contributions` - View contributions for a campaign

## Key Features

1. **Secure Escrow System**: Funds are locked in escrow until contributions are verified
2. **Quality-Based Rewards**: Contributors are rewarded based on the quality of their submissions
3. **Reputation System**: Track and reward reliable contributors
4. **Automated Verification**: Built-in verification mechanisms to ensure data quality
5. **Platform Fee Structure**: Configurable fee structure for platform sustainability

## Getting Started

### Prerequisites

- Aptos CLI
- Node.js and npm
- TypeScript

### Installation

1. Clone the repository

```bash
git clone https://github.com/your-org/hyvve-contracts.git
cd hyvve-contracts
```

2. Install dependencies

```bash
npm install
```

3. Compile the Move contracts

```bash
aptos move compile
```

### Usage Examples

#### Creating a Campaign

```bash
hyvve-cli campaign create_campaign
```

#### Submitting a Contribution

```bash
hyvve-cli contribution submit_contribution
```

#### Checking Campaign Status

```bash
hyvve-cli campaign list_active_campaigns
```

## License

[MIT License](LICENSE)
