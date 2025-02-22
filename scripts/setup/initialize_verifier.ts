import { AptosClient, AptosAccount, HexString, TxnBuilderTypes } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const NODE_URL = process.env.RPC_URL || '';
const MAX_RETRIES = 5;
const RETRY_DELAY_MS = 2000;

async function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function verifyContractState(
  client: AptosClient,
  campaignManagerAddress: string,
  retryCount = 0
): Promise<boolean> {
  try {
    const resources = await client.getAccountResources(campaignManagerAddress);

    const verifierRegistry = resources.find(
      (r) => r.type === `${campaignManagerAddress}::verifier::VerifierRegistry`
    );

    const verifierStore = resources.find(
      (r) => r.type === `${campaignManagerAddress}::verifier::VerifierStore`
    );

    if (verifierRegistry && verifierStore) {
      console.log('\nContract state verification successful:');
      console.log('\nVerifier Registry found:');
      console.log(JSON.stringify(verifierRegistry.data, null, 2));
      console.log('\nVerifier Store found:');
      console.log(JSON.stringify(verifierStore.data, null, 2));
      return true;
    }

    if (retryCount < MAX_RETRIES) {
      console.log(
        `\nWaiting for contract state to be available (attempt ${
          retryCount + 1
        }/${MAX_RETRIES})...`
      );
      await sleep(RETRY_DELAY_MS);
      return verifyContractState(
        client,
        campaignManagerAddress,
        retryCount + 1
      );
    }

    console.log(
      '\nWarning: Contract state verification failed after maximum retries:'
    );
    if (!verifierRegistry) {
      console.log('- Verifier Registry not found');
    }
    if (!verifierStore) {
      console.log('- Verifier Store not found');
    }
    console.log('\nThis might indicate that:');
    console.log('1. The module needs to be published first, or');
    console.log('2. The transaction is still being processed, or');
    console.log('3. There was an error during initialization');
    return false;
  } catch (error) {
    console.error('Error verifying contract state:', error);
    return false;
  }
}

async function main() {
  try {
    const client = new AptosClient(NODE_URL);

    // Initialize admin account (campaign manager)
    if (!process.env.PRIVATE_KEY) {
      throw new Error('Admin private key not found in .env file');
    }
    const adminAccount = new AptosAccount(
      HexString.ensure(process.env.PRIVATE_KEY).toUint8Array()
    );

    console.log('Initializing contract modules...');
    console.log('Admin address:', adminAccount.address().hex());

    // Check if registry already exists
    const resources = await client.getAccountResources(
      process.env.CAMPAIGN_MANAGER_ADDRESS!
    );

    const verifierRegistry = resources.find(
      (r) =>
        r.type ===
        `${process.env.CAMPAIGN_MANAGER_ADDRESS}::verifier::VerifierRegistry`
    );

    if (verifierRegistry) {
      console.log(
        '\nVerifier Registry already exists. Skipping initialization.'
      );
      // Still verify the complete state
      const stateVerified = await verifyContractState(
        client,
        process.env.CAMPAIGN_MANAGER_ADDRESS!
      );
      if (!stateVerified) {
        process.exit(1);
      }
    } else {
      // Initialize the verifier registry
      console.log('\nInitializing verifier registry...');
      const initRegistryPayload = {
        type: 'entry_function_payload',
        function: `${process.env.CAMPAIGN_MANAGER_ADDRESS}::verifier::initialize`,
        type_arguments: [],
        arguments: [],
      };

      try {
        const initTxn = await client.generateTransaction(
          adminAccount.address(),
          initRegistryPayload
        );
        const signedInitTxn = await client.signTransaction(
          adminAccount,
          initTxn
        );
        const initResult = await client.submitTransaction(signedInitTxn);
        await client.waitForTransaction(initResult.hash);
        console.log('Verifier registry initialization transaction successful!');
        console.log('Transaction hash:', initResult.hash);

        // Verify the contract state with retries
        console.log('\nVerifying contract state...');
        const stateVerified = await verifyContractState(
          client,
          process.env.CAMPAIGN_MANAGER_ADDRESS!
        );
        if (!stateVerified) {
          process.exit(1);
        }
      } catch (error: any) {
        console.error(
          'Error initializing verifier registry:',
          error.message || error
        );
        process.exit(1);
      }
    }

    console.log('\nContract initialization complete!');
  } catch (error) {
    console.error('Error initializing contract:', error);
    process.exit(1);
  }
}

main();
