#!/usr/bin/env node

/**
 * Simple CLI for Hyvve Data Marketplace
 * This is a simplified version that doesn't rely on dynamic imports
 */

import { Command } from 'commander';
import fs from 'fs';
import path from 'path';
import { spawn } from 'child_process';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Initialize the CLI program
const program = new Command();

program
  .name('hyvve-cli')
  .description('Hyvve Data Marketplace CLI')
  .version('1.0.0');

// Define command categories and their descriptions
const categories = [
  { name: 'campaign', description: 'Campaign management commands' },
  {
    name: 'contribution',
    description: 'Contribution submission and management',
  },
  { name: 'profile', description: 'User profile management' },
  { name: 'reputation', description: 'Reputation system commands' },
  { name: 'stats', description: 'Statistics and reporting' },
  { name: 'verifier', description: 'Verification tools' },
  { name: 'setup', description: 'Setup and initialization commands' },
];

// Add commands for each category
categories.forEach((category) => {
  const categoryCommand = program.command(category.name);
  categoryCommand.description(category.description);

  // Get the directory for this category
  let categoryDir;
  if (category.name === 'setup') {
    categoryDir = path.join(__dirname, 'setup');
  } else {
    categoryDir = path.join(__dirname, 'cli', category.name);
  }

  // Check if directory exists
  if (fs.existsSync(categoryDir)) {
    // Get all command files in the directory
    const files = fs.readdirSync(categoryDir);

    // Add a command for each file
    files.forEach((file) => {
      if (file.endsWith('.ts') || file.endsWith('.js')) {
        const commandName = file.replace(/\.(ts|js)$/, '');
        const commandPath =
          category.name === 'setup'
            ? path.join(__dirname, 'setup', file)
            : path.join(__dirname, 'cli', category.name, file);

        // Format the command name for the description
        const formattedName = commandName
          .split('_')
          .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
          .join(' ');

        // Add the command
        categoryCommand
          .command(commandName)
          .description(formattedName)
          .action(() => {
            console.log(`Executing ${category.name}/${commandName}...`);

            // Execute the command
            const process = spawn('npx', ['ts-node', commandPath], {
              stdio: 'inherit',
              shell: true,
            });

            process.on('error', (error) => {
              console.error(`Failed to execute command: ${error.message}`);
              process.exit(1);
            });

            process.on('close', (code) => {
              if (code !== 0) {
                console.error(`Command exited with code ${code}`);
                process.exit(code || 1);
              }
            });
          });
      }
    });
  } else {
    // If the directory doesn't exist, add a placeholder command
    categoryCommand
      .command('help')
      .description(`Show available ${category.name} commands`)
      .action(() => {
        console.log(
          `No ${category.name} commands found. Directory does not exist.`
        );
      });
  }
});

// Parse command line arguments
program.parse(process.argv);

// If no arguments provided, show help
if (process.argv.length <= 2) {
  program.help();
}
