import { Command } from 'commander';
import path from 'path';
import fs from 'fs';
import { spawn } from 'child_process';
import { fileURLToPath } from 'url';

// Get the directory name
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Try to import config, but don't fail if it doesn't exist
let CONFIG = {};
let validateConfig = () => {};
try {
  const configModule = await import('./config/index.js');
  CONFIG = configModule.CONFIG;
  validateConfig = configModule.validateConfig;
} catch (error) {
  console.warn(
    'Warning: Could not load config. Some commands may not work properly.'
  );
}

// Initialize the CLI program
const program = new Command();

program
  .name('hyvve-cli')
  .description('Hyvve Data Marketplace CLI')
  .version('1.0.0');

// Define command categories based on folder structure
const COMMAND_CATEGORIES = [
  'campaign',
  'contribution',
  'profile',
  'reputation',
  'stats',
  'verifier',
];

// Setup commands
function setupCommands() {
  // For each category, create a subcommand
  COMMAND_CATEGORIES.forEach((category) => {
    const categoryCommand = program.command(category);
    categoryCommand.description(`Commands related to ${category}`);

    // Get all command files in the category directory
    const categoryDir = path.join(__dirname, 'cli', category);
    if (fs.existsSync(categoryDir)) {
      const files = fs.readdirSync(categoryDir);

      // For each command file, create a subcommand
      files.forEach((file) => {
        if (file.endsWith('.ts') || file.endsWith('.js')) {
          const commandName = file.replace(/\.(ts|js)$/, '');
          const commandPath = path.join('./cli', category, file);

          // Create subcommand
          const command = categoryCommand.command(commandName);

          // Set description based on command name
          command.description(`${formatCommandName(commandName)}`);

          // Add action to execute the command
          command.action(() => {
            console.log(`Executing ${category}/${commandName}...`);
            executeCommand(commandPath);
          });
        }
      });
    }
  });

  // Add setup commands
  const setupCommand = program.command('setup');
  setupCommand.description('Setup and initialization commands');

  const setupDir = path.join(__dirname, 'setup');
  if (fs.existsSync(setupDir)) {
    const files = fs.readdirSync(setupDir);

    files.forEach((file) => {
      if (file.endsWith('.ts') || file.endsWith('.js')) {
        const commandName = file.replace(/\.(ts|js)$/, '');
        const commandPath = path.join('./setup', file);

        const command = setupCommand.command(commandName);
        command.description(`${formatCommandName(commandName)}`);

        command.action(() => {
          console.log(`Executing setup/${commandName}...`);
          executeCommand(commandPath);
        });
      }
    });
  }
}

// Helper function to format command names for descriptions
function formatCommandName(name: string): string {
  return name
    .split('_')
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}

// Execute a command script
function executeCommand(scriptPath: string) {
  try {
    // Validate configuration before running any command
    try {
      validateConfig();
    } catch (error) {
      console.warn(
        'Warning: Configuration validation failed. Command may not work properly.'
      );
    }

    // Use ts-node to execute the TypeScript file
    const tsNode = spawn('npx', ['ts-node', scriptPath], {
      stdio: 'inherit',
      shell: true,
    });

    tsNode.on('error', (error) => {
      console.error(`Failed to execute command: ${error.message}`);
      process.exit(1);
    });

    tsNode.on('close', (code) => {
      if (code !== 0) {
        console.error(`Command exited with code ${code}`);
        process.exit(code || 1);
      }
    });
  } catch (error) {
    console.error('Error executing command:', error);
    process.exit(1);
  }
}

// Setup all commands
setupCommands();

// Parse command line arguments
program.parse(process.argv);

// If no arguments provided, show help
if (process.argv.length <= 2) {
  program.help();
}
