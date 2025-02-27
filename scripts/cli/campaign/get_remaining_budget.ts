import { AptosClient, AptosAccount, HexString } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const NODE_URL = process.env.RPC_URL || '';

async function main() {
  try {
    // Check if campaign ID is provided
    const campaignId = process.argv[2];
    if (!campaignId) {
      console.error('Please provide a campaign ID as an argument');
      process.exit(1);
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

    console.log(`Fetching remaining budget for campaign: ${campaignId}`);
    const moduleAddress = account.address().toString();

    // Get remaining budget using view function
    const remainingBudget = await client.view({
      function: `${moduleAddress}::escrow::get_available_balance`,
      type_arguments: ['0x1::aptos_coin::AptosCoin'],
      arguments: [campaignId],
    });

    if (remainingBudget && remainingBudget[0]) {
      const budget = remainingBudget[0];
      console.log('\nCampaign Budget Details:');
      console.log(`Campaign ID: ${campaignId}`);
      console.log(`Remaining Budget: ${budget} Octas`);
      console.log(`Remaining Budget in APT: ${Number(budget) / 100000000} APT`);
    } else {
      console.log('No budget information found for the campaign.');
    }
  } catch (error) {
    console.error('Error fetching campaign budget:', error);
    process.exit(1);
  }
}

main();
