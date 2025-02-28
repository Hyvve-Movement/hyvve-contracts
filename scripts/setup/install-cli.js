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

// Create symlink to make the CLI globally available
try {
  console.log('Creating symlink for global access...');
  execSync('npm link', { cwd: rootDir, stdio: 'inherit' });
  console.log('Symlink created successfully!');
} catch (error) {
  console.error('Failed to create symlink:', error.message);
  console.log(
    'You may need to run this script with sudo or administrator privileges.'
  );
  process.exit(1);
}

console.log('\nHyvve CLI installed successfully!');
console.log('\nYou can now use the CLI by running:');
console.log('  hyvve-cli <command>');
console.log('\nFor example:');
console.log('  hyvve-cli campaign list_active_campaigns');
console.log('\nTo see all available commands, run:');
console.log('  hyvve-cli --help');
