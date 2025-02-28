#!/usr/bin/env node

// This is a simple wrapper script to make it easier to run the CLI
// You can make this executable with: chmod +x scripts/hyvve-cli.js
// Then you can run it directly: ./scripts/hyvve-cli.js

import { spawn } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Check if ts-node is installed
try {
  const result = spawn('npx', ['--no-install', 'ts-node', '--version'], {
    stdio: 'pipe',
    shell: true,
  });

  result.on('error', () => {
    console.error(
      'Error: ts-node is not installed. Please run "npm install -g ts-node" first.'
    );
    process.exit(1);
  });
} catch (error) {
  console.error('Error checking for ts-node:', error.message);
}

// Check if the CLI file exists
const cliPath = path.join(__dirname, 'cli.ts');
if (!fs.existsSync(cliPath)) {
  console.error(`Error: CLI file not found at ${cliPath}`);
  process.exit(1);
}

console.log('Starting Hyvve CLI...');

// Run the CLI with ts-node
const args = process.argv.slice(2);
const tsNode = spawn(
  'node',
  ['--loader', 'ts-node/esm', path.join(__dirname, 'cli.ts'), ...args],
  {
    stdio: 'inherit',
    shell: true,
  }
);

tsNode.on('error', (error) => {
  console.error(`Failed to execute command: ${error.message}`);
  process.exit(1);
});

tsNode.on('close', (code) => {
  process.exit(code || 0);
});
