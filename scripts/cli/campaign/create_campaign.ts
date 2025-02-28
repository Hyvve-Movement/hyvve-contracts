import { AptosClient, AptosAccount, TxnBuilderTypes, HexString } from 'aptos';
import { CONFIG, validateConfig } from '../../config';
import {
  getAptosClient,
  getAccount,
  submitTransaction,
} from '../../utils/common';

async function main() {
  try {
    // Validate configuration
    validateConfig();

    // Initialize Aptos client
    const client = await getAptosClient();

    // Initialize account from private key
    const account = await getAccount();

    // Campaign parameters
    const campaignId = 'test_campaign_86';
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
      function: `${CONFIG.CAMPAIGN_MANAGER_ADDRESS}::campaign::create_campaign`,
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
    const txnHash = await submitTransaction(client, account, payload);

    console.log(
      'View on explorer:',
      `https://explorer.aptoslabs.com/txn/${txnHash}?network=testnet`
    );
  } catch (error) {
    console.error('Error creating campaign:', error);
    process.exit(1);
  }
}

// If the file is run directly
if (require.main === module) {
  main();
}

// Export for CLI integration
export default main;
