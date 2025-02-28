import { AptosClient, AptosAccount, HexString } from 'aptos';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// Load environment variables
dotenv.config();

const NODE_URL = process.env.RPC_URL || '';

// Function to find the project root directory (where .env is located)
function findProjectRoot() {
  // Try to find .env in current directory and parent directories
  let currentDir = process.cwd();
  const maxDepth = 5; // Limit how far up we go

  for (let i = 0; i < maxDepth; i++) {
    if (fs.existsSync(path.join(currentDir, '.env'))) {
      return currentDir;
    }

    // Go up one directory
    const parentDir = path.dirname(currentDir);
    if (parentDir === currentDir) {
      // We've reached the root of the filesystem
      break;
    }
    currentDir = parentDir;
  }

  // If we can't find it, try to use the directory where this script is located
  try {
    const scriptDir = path.dirname(fileURLToPath(import.meta.url));
    let dir = scriptDir;

    for (let i = 0; i < maxDepth; i++) {
      if (fs.existsSync(path.join(dir, '.env'))) {
        return dir;
      }

      dir = path.dirname(dir);
      if (dir === path.dirname(dir)) {
        break;
      }
    }
  } catch (error) {
    // Ignore errors with fileURLToPath
  }

  // Default to current working directory
  return process.cwd();
}

// Function to update .env file with new verifier credentials
function updateEnvFile(verifierAddress: string, verifierPrivateKey: string) {
  try {
    // Find the project root directory
    const projectRoot = findProjectRoot();
    const envPath = path.join(projectRoot, '.env');

    console.log(`Attempting to update .env file at: ${envPath}`);

    // Check if file exists
    if (!fs.existsSync(envPath)) {
      console.error(`.env file not found at ${envPath}`);
      return false;
    }

    // Read the current .env file
    let envContent = fs.readFileSync(envPath, 'utf8');
    console.log('Successfully read .env file');

    // Update or add VERIFIER_ADDRESS and VERIFIER_PRIVATE_KEY
    const addressRegex = /VERIFIER_ADDRESS=.*/;
    const privateKeyRegex = /VERIFIER_PRIVATE_KEY=.*/;

    if (addressRegex.test(envContent)) {
      // Replace existing values
      console.log('Updating existing verifier credentials in .env file');
      envContent = envContent.replace(
        addressRegex,
        `VERIFIER_ADDRESS=${verifierAddress}`
      );
      envContent = envContent.replace(
        privateKeyRegex,
        `VERIFIER_PRIVATE_KEY=${verifierPrivateKey}`
      );
    } else {
      // Add new values
      console.log('Adding new verifier credentials to .env file');
      envContent += `\nVERIFIER_ADDRESS=${verifierAddress}`;
      envContent += `\nVERIFIER_PRIVATE_KEY=${verifierPrivateKey}`;
    }

    // Write the updated content back to .env
    fs.writeFileSync(envPath, envContent);
    console.log('.env file updated successfully with new verifier credentials');
    return true;
  } catch (error) {
    console.error('Error updating .env file:', error);
    return false;
  }
}

async function main() {
  try {
    // Initialize Aptos client
    const client = new AptosClient(NODE_URL);

    // Initialize admin account from private key
    if (!process.env.PRIVATE_KEY) {
      throw new Error('Private key not found in .env file');
    }
    const adminAccount = new AptosAccount(
      HexString.ensure(process.env.PRIVATE_KEY).toUint8Array()
    );

    // Create a new account for the verifier if not using an existing one
    const verifierAccount = new AptosAccount();
    console.log('Generated new verifier account:');
    console.log('Address:', verifierAccount.address().hex());
    console.log(
      'Private key:',
      verifierAccount.toPrivateKeyObject().privateKeyHex
    );
    console.log('Public key:', verifierAccount.pubKey().hex());

    // Fund the verifier account with some APT for gas
    const fundAmount = 100_000_000; // 1 APT = 100_000_000 Octas
    const fundPayload = {
      type: 'entry_function_payload',
      function: '0x1::aptos_account::transfer',
      type_arguments: [],
      arguments: [verifierAccount.address().hex(), fundAmount.toString()],
    };

    console.log('\nFunding verifier account...');
    const fundTxn = await client.generateTransaction(
      adminAccount.address(),
      fundPayload
    );
    const signedFundTxn = await client.signTransaction(adminAccount, fundTxn);
    const fundTxnResult = await client.submitTransaction(signedFundTxn);
    await client.waitForTransaction(fundTxnResult.hash);
    console.log('Verifier account funded successfully');

    // Register the verifier
    console.log('\nRegistering verifier...');
    const moduleAddress = adminAccount.address().toString();
    const registerPayload = {
      type: 'entry_function_payload',
      function: `${moduleAddress}::verifier::add_verifier`,
      type_arguments: [],
      arguments: [
        verifierAccount.address().hex(),
        Array.from(verifierAccount.pubKey().toUint8Array()),
      ],
    };

    const txnRequest = await client.generateTransaction(
      adminAccount.address(),
      registerPayload
    );
    const signedTxn = await client.signTransaction(adminAccount, txnRequest);
    const txnResult = await client.submitTransaction(signedTxn);

    console.log('Transaction submitted!');
    console.log('Transaction hash:', txnResult.hash);

    await client.waitForTransaction(txnResult.hash);
    console.log('Verifier registered successfully!');
    console.log(
      'View on explorer:',
      `https://explorer.aptoslabs.com/txn/${txnResult.hash}?network=testnet`
    );

    // Update .env file with new verifier credentials
    const verifierAddress = verifierAccount.address().hex();
    const verifierPrivateKey =
      verifierAccount.toPrivateKeyObject().privateKeyHex;

    // Update the .env file
    const updated = updateEnvFile(verifierAddress, verifierPrivateKey);

    if (updated) {
      console.log('\nIMPORTANT: Credentials saved to .env file:');
    } else {
      console.log('\nIMPORTANT: Save these credentials securely:');
    }

    console.log('Verifier address:', verifierAddress);
    console.log('Verifier private key:', verifierPrivateKey);

    if (!updated) {
      console.log(
        "\nPlease manually update your .env file with the verifier's credentials for submitting contributions"
      );
    }
  } catch (error) {
    console.error('Error registering verifier:', error);
    process.exit(1);
  }
}

main();
