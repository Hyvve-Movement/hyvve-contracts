import { AptosClient, AptosAccount, TxnBuilderTypes, HexString } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const CAMPAIGN_MANAGER_ADDRESS = process.env.CAMPAIGN_MANAGER_ADDRESS || '';
const NODE_URL = process.env.RPC_URL || '';

async function main() {
  try {
    // Initialize Aptos client
    const client = new AptosClient(NODE_URL);

    // Initialize account from private key
    if (!process.env.PRIVATE_KEY) {
      throw new Error('Private key not found in .env file');
    }
    const account = new AptosAccount(
      HexString.ensure(process.env.PRIVATE_KEY).toUint8Array()
    );

    // Campaign parameters
    const campaignId = 'test_campaign_1';
    const title = 'Test Campaign';
    const description = 'A test campaign created via script';
    const dataRequirements = 'Test data requirements';
    const qualityCriteria = 'Test quality criteria';
    const unitPrice = 100; // in Octas
    const totalBudget = 1000; // in Octas
    const minDataCount = 5;
    const maxDataCount = 10;
    const expiration = Math.floor(Date.now() / 1000) + 86400; // 24 hours from now
    const metadataUri = 'ipfs://test';
    const platformFee = 10;
    const encryptionPubKey = new Uint8Array([1, 2, 3, 4]);

    // Create payload
    const payload = {
      type: 'entry_function_payload',
      function: `${CAMPAIGN_MANAGER_ADDRESS}::campaign::create_campaign`,
      type_arguments: ['0x1::aptos_coin::AptosCoin'],
      arguments: [
        campaignId,
        title,
        description,
        dataRequirements,
        qualityCriteria,
        unitPrice,
        totalBudget,
        minDataCount,
        maxDataCount,
        expiration,
        metadataUri,
        platformFee,
        Array.from(encryptionPubKey), // Convert Uint8Array to regular array for serialization
      ],
    };

    // Submit transaction
    const txnRequest = await client.generateTransaction(
      account.address(),
      payload
    );
    const signedTxn = await client.signTransaction(account, txnRequest);
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
    console.error('Error creating campaign:', error);
    process.exit(1);
  }
}

main();
