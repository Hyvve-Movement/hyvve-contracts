#!/usr/bin/env node

import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..', '..');

console.log('Uninstalling Hyvve CLI...');

// Try to unlink the CLI
try {
  console.log('Removing global symlink...');
  execSync('npm unlink -g hyvve-cli', { stdio: 'inherit' });
  console.log('Global symlink removed successfully!');
} catch (error) {
  console.error('Failed to unlink CLI:', error.message);

  // Try to manually remove the symlink
  try {
    console.log('Attempting to manually remove symlink...');
    const cliPath = execSync('which hyvve-cli', { encoding: 'utf8' }).trim();

    if (fs.existsSync(cliPath)) {
      fs.unlinkSync(cliPath);
      console.log(`Manually removed symlink at ${cliPath}`);
    } else {
      console.log('No symlink found at expected location');
    }
  } catch (manualError) {
    console.error('Could not manually remove symlink:', manualError.message);
    console.log('You may need to manually remove the symlink:');
    console.log('  rm $(which hyvve-cli)');
  }
}

console.log('\nHyvve CLI has been uninstalled.');
console.log('You can still use the CLI locally with:');
console.log('  npm run cli -- <category> <command>');
