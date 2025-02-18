import { AptosClient, AptosAccount, HexString } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const NODE_URL = 'https://aptos.testnet.bardock.movementlabs.xyz/v1';

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

    console.log('Fetching active campaigns...');
    const moduleAddress = account.address().toString();

    // Get active campaigns using view function
    const activeCampaigns = await client.view({
      function: `${moduleAddress}::campaign::get_active_campaigns`,
      type_arguments: [],
      arguments: [moduleAddress],
    });

    if (activeCampaigns && Array.isArray(activeCampaigns[0])) {
      const campaigns = activeCampaigns[0];
      console.log(`Found ${campaigns.length} active campaigns:\n`);

      campaigns.forEach((campaign: any, index: number) => {
        console.log(`Campaign ${index + 1}:`);
        console.log(`ID: ${campaign.campaign_id}`);
        console.log(`Title: ${campaign.title}`);
        console.log(`Description: ${campaign.description}`);
        console.log(`Owner: ${campaign.owner}`);
        console.log(`Unit Price: ${campaign.unit_price} Octas`);
        console.log(`Total Budget: ${campaign.total_budget} Octas`);
        console.log(`Data Requirements: ${campaign.data_requirements}`);
        console.log(`Quality Criteria: ${campaign.quality_criteria}`);
        console.log(`Min Data Count: ${campaign.min_data_count}`);
        console.log(`Max Data Count: ${campaign.max_data_count}`);
        console.log(`Current Contributions: ${campaign.total_contributions}`);
        console.log(`Metadata URI: ${campaign.metadata_uri}`);
        console.log(
          `Expiration: ${new Date(
            Number(campaign.expiration) * 1000
          ).toLocaleString()}`
        );
        console.log('-------------------\n');
      });
    } else {
      console.log('No active campaigns found.');
    }
  } catch (error) {
    console.error('Error fetching active campaigns:', error);
    process.exit(1);
  }
}

main();
