import { AptosClient, AptosAccount, HexString } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const NODE_URL = 'https://aptos.testnet.porto.movementlabs.xyz/v1';

async function main() {
  try {
    const client = new AptosClient(NODE_URL);

    // Get verifier account
    if (!process.env.VERIFIER_PRIVATE_KEY) {
      throw new Error('Verifier private key not found in .env file');
    }
    const verifierAccount = new AptosAccount(
      HexString.ensure(process.env.VERIFIER_PRIVATE_KEY).toUint8Array()
    );

    console.log('Checking verifier registration...');
    console.log('Verifier address:', verifierAccount.address().hex());
    console.log(
      'Verifier public key:',
      Array.from(verifierAccount.pubKey().toUint8Array())
    );

    // Check if verifier registry exists
    const resources = await client.getAccountResources(
      process.env.CAMPAIGN_MANAGER_ADDRESS
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

    console.log('\nChecking contract state:');
    if (verifierRegistry) {
      console.log('\nVerifier Registry found:');
      console.log(JSON.stringify(verifierRegistry.data, null, 2));
    } else {
      console.log('Verifier Registry not found!');
    }

    if (verifierStore) {
      console.log('\nVerifier Store found:');
      console.log(JSON.stringify(verifierStore.data, null, 2));
    } else {
      console.log('Verifier Store not found!');
    }

    // Check if this verifier is registered
    if (verifierRegistry) {
      const verifiers = verifierRegistry.data.verifiers;
      const isRegistered = verifiers.some(
        (v: any) => v.address === verifierAccount.address().hex()
      );
      console.log(
        '\nVerifier registration status:',
        isRegistered ? 'Registered' : 'Not registered'
      );
    }
  } catch (error) {
    console.error('Error checking verifier:', error);
    process.exit(1);
  }
}

main();
