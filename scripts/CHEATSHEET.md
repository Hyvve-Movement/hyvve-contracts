# Hyvve CLI Cheat Sheet

This cheat sheet provides a quick reference for all available commands in the Hyvve Data Marketplace CLI.

## Installation

```bash
# Navigate to the project directory
cd hyvve-contracts

# Install dependencies
npm install

# Install the CLI globally
npm link
```

## Basic Usage

```bash
# Using the global command
hyvve-cli <category> <command> [options]

# Using npm
npm run cli -- <category> <command> [options]
```

## Getting Help

```bash
# Show all available categories
hyvve-cli --help

# Show commands in a specific category
hyvve-cli campaign --help
hyvve-cli contribution --help
```

## Campaign Management

| Command                 | Description                               | Usage                                                   |
| ----------------------- | ----------------------------------------- | ------------------------------------------------------- |
| `create_campaign`       | Create a new data collection campaign     | `hyvve-cli campaign create_campaign`                    |
| `list_active_campaigns` | List all active campaigns                 | `hyvve-cli campaign list_active_campaigns`              |
| `get_campaign_pubkey`   | Get the public key for a campaign         | `hyvve-cli campaign get_campaign_pubkey <campaign_id>`  |
| `get_remaining_budget`  | Check the remaining budget for a campaign | `hyvve-cli campaign get_remaining_budget <campaign_id>` |

## Contribution Management

| Command               | Description                                  | Usage                                                                                 |
| --------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------- |
| `submit_contribution` | Submit a new data contribution to a campaign | `hyvve-cli contribution submit_contribution <campaign_id> <data_url> <quality_score>` |
| `get_contributions`   | View contributions for a campaign            | `hyvve-cli contribution get_contributions [campaign_id] [contributor_address]`        |

## Campaign Statistics

| Command               | Description                     | Usage                                           |
| --------------------- | ------------------------------- | ----------------------------------------------- |
| `activity`            | View activity statistics        | `hyvve-cli stats activity [address]`            |
| `check_address_stats` | Check statistics for an address | `hyvve-cli stats check_address_stats [address]` |

## Verifier Management

| Command                 | Description             | Usage                                      |
| ----------------------- | ----------------------- | ------------------------------------------ |
| `register_verifier`     | Register a new verifier | `hyvve-cli verifier register_verifier`     |
| `register_verifier_key` | Register a verifier key | `hyvve-cli verifier register_verifier_key` |
| `check_verifier`        | Check verifier status   | `hyvve-cli verifier check_verifier`        |

## Reputation Management

| Command          | Description                   | Usage                                           |
| ---------------- | ----------------------------- | ----------------------------------------------- |
| `get_reputation` | Get reputation for an address | `hyvve-cli reputation get_reputation [address]` |

## Profile Management

| Command               | Description              | Usage                                              |
| --------------------- | ------------------------ | -------------------------------------------------- |
| `manage_profile set`  | Set a new profile        | `hyvve-cli profile manage_profile set <username>`  |
| `manage_profile edit` | Edit an existing profile | `hyvve-cli profile manage_profile edit <username>` |
| `manage_profile view` | View a profile           | `hyvve-cli profile manage_profile view [address]`  |

## Setup and Initialization

| Command               | Description                        | Usage                                 |
| --------------------- | ---------------------------------- | ------------------------------------- |
| `initialize_verifier` | Initialize the verification system | `hyvve-cli setup initialize_verifier` |
| `subscription`        | Set up subscription management     | `hyvve-cli setup subscription`        |

## Notes

- Parameters in `<angle_brackets>` are required
- Parameters in `[square_brackets]` are optional
- If no address is provided for stats commands, uses the account from PRIVATE_KEY in .env
- For `get_contributions`:
  - Provide `campaign_id` to view all contributions for a campaign
  - Provide `contributor_address` to view all contributions by an address
  - Provide both to filter contributions by campaign and contributor

## Environment Configuration

Make sure to set up your environment variables in a `.env` file at the root of the project:

```
CAMPAIGN_MANAGER_ADDRESS=0x...
RPC_URL=https://fullnode.testnet.aptoslabs.com/v1
PRIVATE_KEY=0x...
```
