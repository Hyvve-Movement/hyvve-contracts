import { AptosClient, AptosAccount, HexString } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const NODE_URL = process.env.RPC_URL || '';

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

    console.log('\nIMPORTANT: Save these credentials securely:');
    console.log('Verifier address:', verifierAccount.address().hex());
    console.log(
      'Verifier private key:',
      verifierAccount.toPrivateKeyObject().privateKeyHex
    );
    console.log(
      "\nUpdate your .env file with the verifier's private key to use it for submitting contributions"
    );
  } catch (error) {
    console.error('Error registering verifier:', error);
    process.exit(1);
  }
}

main();
