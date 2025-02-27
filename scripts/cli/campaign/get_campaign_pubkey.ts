import { AptosClient, AptosAccount, HexString } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const NODE_URL = process.env.RPC_URL || '';

async function main() {
  try {
    // Get campaign ID from command line arguments
    const campaignId = process.argv[2];
    if (!campaignId) {
      throw new Error(
        'Campaign ID is required. Usage: npx ts-node get_campaign_pubkey.ts <campaign_id> [campaign_address]'
      );
    }

    // Initialize Aptos client
    const client = new AptosClient(NODE_URL);

    // Initialize account from private key
    if (!process.env.PRIVATE_KEY) {
      throw new Error('Private key not found in .env file');
    }
    const account = new AptosAccount(
      HexString.ensure(process.env.PRIVATE_KEY).toUint8Array()
    );

    // Use provided campaign address or default to campaign manager address
    const campaignAddress = process.argv[3] || account.address().toString();

    console.log('Fetching campaign public key...');
    console.log(`Campaign ID: ${campaignId}`);
    console.log(`Campaign Address: ${campaignAddress}`);

    // Get campaign public key using view function
    const result = await client.view({
      function: `${campaignAddress}::campaign::get_encryption_public_key`,
      type_arguments: [],
      arguments: [campaignAddress, campaignId],
    });

    if (result && result[0]) {
      const pubKey = result[0];
      console.log('\nPublic Key:');
      if (Array.isArray(pubKey)) {
        // Convert byte array to hex string
        const hexString = HexString.fromUint8Array(
          new Uint8Array(pubKey)
        ).toString();
        console.log(hexString);
      } else {
        console.log(pubKey);
      }
    } else {
      console.log('No public key found for the specified campaign.');
    }
  } catch (error) {
    console.error('Error fetching campaign public key:', error);
    process.exit(1);
  }
}

main();
