import { AptosClient, AptosAccount, HexString, TxnBuilderTypes } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const NODE_URL = process.env.RPC_URL || '';

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

    // Initialize the verifier registry (which also initializes the store via init_module)
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
      const signedInitTxn = await client.signTransaction(adminAccount, initTxn);
      const initResult = await client.submitTransaction(signedInitTxn);
      await client.waitForTransaction(initResult.hash);
      console.log('Verifier registry and store initialized!');
      console.log('Transaction hash:', initResult.hash);
    } catch (error: any) {
      console.error(
        'Error initializing verifier registry:',
        error.message || error
      );
    }

    // Verify initialization
    console.log('\nVerifying initialization...');
    const resources = await client.getAccountResources(
      process.env.CAMPAIGN_MANAGER_ADDRESS!
    );

    const verifierRegistry = resources.find(
      (r) =>
        r.type ===
        `${process.env.CAMPAIGN_MANAGER_ADDRESS}::verifier::VerifierRegistry`
    );

    const verifierStore = resources.find(
      (r) =>
        r.type ===
        `${process.env.CAMPAIGN_MANAGER_ADDRESS}::verifier::VerifierStore`
    );

    if (verifierRegistry) {
      console.log('\nVerifier Registry found:');
      console.log(JSON.stringify(verifierRegistry.data, null, 2));
    } else {
      console.log('Warning: Verifier Registry not found!');
    }

    if (verifierStore) {
      console.log('\nVerifier Store found:');
      console.log(JSON.stringify(verifierStore.data, null, 2));
    } else {
      console.log('Warning: Verifier Store not found!');
    }

    console.log('\nContract initialization complete!');
  } catch (error) {
    console.error('Error initializing contract:', error);
    process.exit(1);
  }
}

main();
