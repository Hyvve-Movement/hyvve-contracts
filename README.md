# Hyvve Data Marketplace - Smart Contracts

A decentralized marketplace for data collection and contribution built on the Aptos blockchain.

## Table of Contents

- [Overview](#overview)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Environment Configuration](#environment-configuration)
- [CLI Commands](#cli-commands)
  - [Installation](#installation)
  - [Troubleshooting Installation](#troubleshooting-installation)
  - [Usage Examples](#usage-examples)
  - [Campaign Management](#campaign-management)
  - [Contribution Management](#contribution-management)
  - [CLI Cheatsheet](#cli-cheatsheet)
- [Key Features](#key-features)
- [License](#license)

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

## Getting Started

### Prerequisites

- Aptos CLI 3.5 / [Movement CLI](https://docs.movementnetwork.xyz/devs/movementcli)
- Node.js and npm
- TypeScript

### Environment Configuration

The project uses environment variables for configuration. A sample `.env.example` file is provided:

```
CAMPAIGN_MANAGER_ADDRESS=0x1
PRIVATE_KEY=0x1

VERIFIER_ADDRESS=
VERIFIER_PRIVATE_KEY=

NETWORK=testnet
RPC_URL=https://aptos.testnet.bardock.movementlabs.xyz/v1
```

To set up your environment:

1. Copy the `.env.example` file to `.env`:

   ```bash
   cp .env.example .env
   ```

2. Update the values in `.env` with your specific configuration:
   - `CAMPAIGN_MANAGER_ADDRESS`: Your account address for campaign management
   - `PRIVATE_KEY`: Your account private key
   - `VERIFIER_ADDRESS`: Address for the verifier account (optional) 
   - `VERIFIER_PRIVATE_KEY`: Private key for the verifier account (optional)
   - `NETWORK`: Network to connect to (default: testnet)
   - `RPC_URL`: URL for the RPC endpoint

**Note**: Keep your private keys secure and never commit your `.env` file to version control.
**Note**: A new Verifier Address and private key will be generated when registering a new verifier

### CLI Commands

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

# Setup Movement CLI
movement init --skip-faucet
```

You will be prompted to choose a network and an endpoint:

- Network: custom
- Rest endpoint: https://aptos.testnet.bardock.movementlabs.xyz/v1

Once your `.movement` folder is created, you need to update `.env`:

```
CAMPAIGN_MANAGER_ADDRESS=<account address>
PRIVATE_KEY=<account private key>
```

Register Verifier and Verifier Keys:

```bash
hyvve-cli verifier register_verifier
hyvve-cli verifier register_verifier_key
```

### Troubleshooting Installation

If you encounter any issues during installation:

1. **Existing Installation**: If you see an error about an existing file, you can try:

   ```bash
   # Remove existing symlink
   rm $(which hyvve-cli)

   # Then run the installation script again
   node scripts/setup/install-cli.js
   ```

2. **Permission Issues**: If you encounter permission errors:

   ```bash
   sudo node scripts/setup/install-cli.js
   ```

3. **Alternative Usage**: You can always use the CLI without global installation:
   ```bash
   npm run cli -- <category> <command>
   ```

### Usage Examples

Once installed, you can use the CLI with the following syntax:

```bash
# Using the global command
hyvve-cli <category> <command>

# Alternative: Using npm run
npm run cli -- <category> <command>
```

For example:

```bash
# Using global command
hyvve-cli campaign create_campaign
hyvve-cli contribution submit_contribution

# Using npm run
npm run cli -- campaign create_campaign
npm run cli -- contribution submit_contribution
```

#### Submitting a Contribution

```bash
hyvve-cli contribution submit_contribution
```

#### Checking Campaign Status

```bash
hyvve-cli campaign list_active_campaigns
```

To see all available commands:

```bash
hyvve-cli --help
```

### Campaign Management

- `campaign create_campaign` - Create a new data collection campaign
- `campaign list_active_campaigns` - List all active campaigns
- `campaign get_campaign_pubkey` - Get the public key for a campaign
- `campaign get_remaining_budget` - Check the remaining budget for a campaign

### Contribution Management

- `contribution submit_contribution` - Submit a new data contribution to a campaign
- `contribution get_contributions` - View contributions for a campaign

### CLI Cheatsheet

For more detailed information about the CLI, we added a comprehensive [CLI documentation](scripts/README.md) and the [CLI Cheat Sheet](scripts/CHEATSHEET.md).

The [CLI Cheatsheet](scripts/CHEATSHEET.md) includes:

- All available command categories
- Command syntax and parameters
- Example usage for common scenarios
- Tips and best practices

This is especially useful for developers who are already familiar with the platform and need a quick reference guide.


## Key Features

1. **Secure Escrow System**: Funds are locked in escrow until contributions are verified
2. **Quality-Based Rewards**: Contributors are rewarded based on the quality of their submissions
3. **Reputation System**: Track and reward reliable contributors
4. **Automated Verification**: Built-in verification mechanisms to ensure data quality
5. **Platform Fee Structure**: Configurable fee structure for platform sustainability

## License

[MIT License](LICENSE)

```

```
