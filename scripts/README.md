# Hyvve Data Marketplace CLI

This directory contains the command-line interface (CLI) tools for interacting with the Hyvve Data Marketplace smart contracts.

## Getting Started

### Prerequisites

- Node.js (v14 or higher)
- npm or yarn
- TypeScript

### Configuration

Before using the CLI, make sure to set up your environment variables in a `.env` file at the root of the project:

```
CAMPAIGN_MANAGER_ADDRESS=0x...
RPC_URL=https://fullnode.testnet.aptoslabs.com/v1
PRIVATE_KEY=0x...
```

### Installation

The CLI is part of the main project. To install dependencies and make the CLI globally available:

```bash
# Navigate to the project directory
cd hyvve-contracts

# Install dependencies
npm install

# Install the CLI globally
npm run setup-cli
# or
node scripts/setup/install-cli.js
```

#### Troubleshooting Installation

If you encounter any issues during installation:

1. **Existing Installation**: If you see an error about an existing file, you can try:
   ```bash
   # Remove existing symlink
   rm $(which hyvve-cli)
   
   # Then run the installation script again
   npm run setup-cli
   ```

2. **Permission Issues**: If you encounter permission errors:
   ```bash
   sudo npm run setup-cli
   # or
   sudo node scripts/setup/install-cli.js
   ```

3. **Alternative Usage**: You can always use the CLI without global installation:
   ```bash
   npm run cli -- <category> <command>
   ```

### Uninstallation

If you need to uninstall the CLI:

```bash
# Using the npm script
npm run uninstall-cli

# Or directly
node scripts/setup/uninstall-cli.js
```

## Usage

Once installed, you can use the CLI with the following syntax:

```bash
# Global command
hyvve-cli <category> <command>

# Using npm run
npm run cli -- <category> <command>
```

For example:

```bash
# Global command
hyvve-cli campaign list_active_campaigns

# Using npm run
npm run cli -- campaign list_active_campaigns
```

To see all available commands:

```bash
hyvve-cli --help
```

### Available Command Categories

- `campaign` - Campaign management commands
- `contribution` - Contribution submission and management
- `profile` - User profile management
- `reputation` - Reputation system commands
- `stats` - Statistics and reporting
- `verifier` - Verification tools
- `setup` - Setup and initialization commands

### Campaign Management Commands

```bash
hyvve-cli campaign --help
```

- `create_campaign` - Create a new data collection campaign
- `list_active_campaigns` - List all active campaigns
- `get_campaign_pubkey` - Get the public key for a campaign
- `get_remaining_budget` - Check the remaining budget for a campaign

### Contribution Management Commands

```bash
hyvve-cli contribution --help
```

- `submit_contribution` - Submit a new data contribution to a campaign
- `get_contributions` - View contributions for a campaign

### Setup Commands

```bash
hyvve-cli setup --help
```

- `initialize_verifier` - Initialize the verification system
- `subscription` - Set up subscription management

## Development

### Adding New Commands

To add a new command:

1. Create a new TypeScript file in the appropriate category directory (e.g., `scripts/cli/campaign/new_command.ts`)
2. The file should export a main function that executes the command
3. The command will automatically be available in the CLI under its category

### Command File Structure

Each command file should follow this basic structure:

```typescript
import { AptosClient, AptosAccount } from 'aptos';
import { CONFIG, validateConfig } from '../../config';
import {
  getAptosClient,
  getAccount,
  submitTransaction,
} from '../../utils/common';

async function main() {
  try {
    // Command implementation
    console.log('Command executed successfully');
  } catch (error) {
    console.error('Error executing command:', error);
    process.exit(1);
  }
}

// If the file is run directly
if (require.main === module) {
  main();
}

// Export for CLI integration
export default main;
```
