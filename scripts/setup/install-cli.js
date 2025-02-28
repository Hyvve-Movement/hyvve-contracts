#!/usr/bin/env node

import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..', '..');

console.log('Installing Hyvve CLI...');

// Check if the simple CLI exists
const simpleCLIPath = path.join(rootDir, 'scripts', 'simple-cli.js');
if (!fs.existsSync(simpleCLIPath)) {
  console.error(`Error: Simple CLI file not found at ${simpleCLIPath}`);
  process.exit(1);
}

// Make sure the simple CLI is executable
try {
  fs.chmodSync(simpleCLIPath, '755');
  console.log('Made CLI script executable');
} catch (error) {
  console.warn('Warning: Could not make CLI script executable:', error.message);
}

// Try to unlink any existing CLI first to avoid conflicts
try {
  console.log('Checking for existing CLI installations...');
  execSync('npm unlink -g hyvve-cli', { stdio: 'pipe' });
  console.log('Unlinked existing CLI installation');
} catch (error) {
  // It's okay if this fails - it might not be installed yet
  console.log('No existing CLI installation found or unable to unlink');
}

// Create symlink to make the CLI globally available
try {
  console.log('Creating symlink for global access...');

  // Use --force flag to overwrite any existing symlinks
  execSync('npm link --force', { cwd: rootDir, stdio: 'inherit' });
  console.log('Symlink created successfully!');
} catch (error) {
  console.error('Failed to create symlink:', error.message);

  // Provide more detailed troubleshooting steps
  console.log('\nTroubleshooting steps:');
  console.log(
    '1. If you see an EEXIST error, try manually removing the symlink:'
  );
  console.log('   rm $(which hyvve-cli)');
  console.log('2. Then run this script again');
  console.log('3. Or you may need to run with sudo:');
  console.log('   sudo node scripts/setup/install-cli.js');
  console.log('\nAlternative installation:');
  console.log('You can also use the CLI without global installation:');
  console.log('npm run cli -- <category> <command>');

  process.exit(1);
}

console.log('\nHyvve CLI installed successfully!');
console.log('\nYou can now use the CLI by running:');
console.log('  hyvve-cli <command>');
console.log('\nFor example:');
console.log('  hyvve-cli campaign list_active_campaigns');
console.log('\nTo see all available commands, run:');
console.log('  hyvve-cli --help');
console.log('\nAlternative usage:');
console.log('  npm run cli -- <category> <command>');
