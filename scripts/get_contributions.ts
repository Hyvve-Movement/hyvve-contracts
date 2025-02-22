import { AptosClient, AptosAccount, HexString } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

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

    // Get campaign ID from command line arguments
    const campaignId = process.argv[2];
    if (!campaignId) {
      console.error('Please provide a campaign ID as an argument');
      console.log(
        'Usage: npx ts-node scripts/get_contributions.ts <campaign_id>'
      );
      process.exit(1);
    }

    console.log(`Fetching contributions for campaign ${campaignId}...`);
    const moduleAddress = account.address().toString();

    // Get contribution store using view function
    const contributionStore = await client.view({
      function: `${moduleAddress}::contribution::get_contribution_store`,
      type_arguments: [],
      arguments: [],
    });

    if (contributionStore && Array.isArray(contributionStore[0])) {
      const contributions = contributionStore[0].filter(
        (contribution: any) => contribution.campaign_id === campaignId
      );

      console.log(`Found ${contributions.length} contributions:\n`);

      contributions.forEach((contribution: any, index: number) => {
        console.log(`Contribution ${index + 1}:`);
        console.log(`ID: ${contribution.contribution_id}`);
        console.log(`Contributor: ${contribution.contributor}`);
        console.log(`Data URL: ${contribution.data_url}`);
        console.log(
          `Data Hash: ${Buffer.from(contribution.data_hash).toString('hex')}`
        );
        console.log(
          `Timestamp: ${new Date(
            Number(contribution.timestamp) * 1000
          ).toLocaleString()}`
        );
        console.log(
          `Verification Status: ${
            contribution.is_verified ? 'Verified' : 'Pending'
          }`
        );
        if (contribution.is_verified) {
          console.log(
            `Verifier Reputation: ${contribution.verification_scores.verifier_reputation}`
          );
          console.log(
            `Quality Score: ${contribution.verification_scores.quality_score}`
          );
        }
        console.log(
          `Reward Status: ${
            contribution.reward_claimed ? 'Claimed' : 'Unclaimed'
          }`
        );
        console.log('-------------------\n');
      });
    } else {
      console.log('No contributions found for this campaign.');
    }
  } catch (error) {
    console.error('Error fetching contributions:', error);
    process.exit(1);
  }
}

main();
