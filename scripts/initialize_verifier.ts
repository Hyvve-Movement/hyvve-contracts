import { AptosClient, AptosAccount, HexString } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const NODE_URL = 'https://aptos.testnet.bardock.movementlabs.xyz/v1';

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

    // Get verifier account
    if (!process.env.VERIFIER_PRIVATE_KEY) {
      throw new Error('Verifier private key not found in .env file');
    }
    const verifierAccount = new AptosAccount(
      HexString.ensure(process.env.VERIFIER_PRIVATE_KEY).toUint8Array()
    );

    console.log('Registering verifier...');
    console.log('Admin address:', adminAccount.address().hex());
    console.log('Verifier address:', verifierAccount.address().hex());
    console.log(
      'Verifier public key:',
      Array.from(verifierAccount.pubKey().toUint8Array())
    );

    // Register the verifier
    const registerPayload = {
      type: 'entry_function_payload',
      function: `${process.env.CAMPAIGN_MANAGER_ADDRESS}::verifier::add_verifier`,
      type_arguments: [],
      arguments: [
        verifierAccount.address().hex(),
        Array.from(verifierAccount.pubKey().toUint8Array()),
      ],
    };

    console.log('\nSubmitting registration...');
    const registerTxn = await client.generateTransaction(
      adminAccount.address(),
      registerPayload
    );
    const signedRegisterTxn = await client.signTransaction(
      adminAccount,
      registerTxn
    );
    const registerResult = await client.submitTransaction(signedRegisterTxn);
    await client.waitForTransaction(registerResult.hash);
    console.log('Verifier registered successfully!');
    console.log('Transaction hash:', registerResult.hash);
    console.log(
      'View on explorer:',
      `https://explorer.aptoslabs.com/txn/${registerResult.hash}?network=testnet`
    );
  } catch (error) {
    console.error('Error registering verifier:', error);
    process.exit(1);
  }
}

main();
