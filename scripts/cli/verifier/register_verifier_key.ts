import { AptosClient, AptosAccount, HexString } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const NODE_URL = process.env.RPC_URL || '';

async function main() {
  try {
    // Initialize Aptos client
    const client = new AptosClient(NODE_URL);

    // Initialize admin account
    if (!process.env.PRIVATE_KEY) {
      throw new Error('Admin private key not found in .env file');
    }
    const adminAccount = new AptosAccount(
      HexString.ensure(process.env.PRIVATE_KEY).toUint8Array()
    );

    // Initialize verifier account to get public key
    if (!process.env.VERIFIER_PRIVATE_KEY) {
      throw new Error('Verifier private key not found in .env file');
    }
    const verifierAccount = new AptosAccount(
      HexString.ensure(process.env.VERIFIER_PRIVATE_KEY).toUint8Array()
    );

    console.log('Registering verifier key...');
    console.log('Admin address:', adminAccount.address().hex());
    console.log(
      'Verifier public key:',
      Array.from(verifierAccount.pubKey().toUint8Array())
    );

    // Create payload to add verifier key
    const payload = {
      type: 'entry_function_payload',
      function: `${process.env.CAMPAIGN_MANAGER_ADDRESS}::verifier::add_verifier_key`,
      type_arguments: [],
      arguments: [Array.from(verifierAccount.pubKey().toUint8Array())],
    };

    // Submit transaction
    const txnRequest = await client.generateTransaction(
      adminAccount.address(),
      payload
    );
    const signedTxn = await client.signTransaction(adminAccount, txnRequest);
    const txnResult = await client.submitTransaction(signedTxn);

    console.log('Transaction submitted!');
    console.log('Transaction hash:', txnResult.hash);

    // Wait for transaction
    await client.waitForTransaction(txnResult.hash);
    console.log('Transaction successful!');
    console.log(
      'View on explorer:',
      `https://explorer.aptoslabs.com/txn/${txnResult.hash}?network=testnet`
    );
  } catch (error) {
    console.error('Error registering verifier key:', error);
    process.exit(1);
  }
}

main();
