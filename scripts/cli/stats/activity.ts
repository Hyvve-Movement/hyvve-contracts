import { AptosClient, AptosAccount, HexString, Types } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const CAMPAIGN_MANAGER_ADDRESS = process.env.CAMPAIGN_MANAGER_ADDRESS || '';
const NODE_URL = process.env.RPC_URL || '';

interface ActivityStats {
  campaigns: {
    total: number;
    active: number;
  };
  contributions: {
    total: number;
    verified: number;
  };
}

async function getActivityStats(
  client: AptosClient,
  address: string
): Promise<ActivityStats> {
  try {
    // Get campaign counts
    const campaignCounts = await client.view({
      function: `${CAMPAIGN_MANAGER_ADDRESS}::campaign::get_address_campaign_count`,
      type_arguments: [],
      arguments: [CAMPAIGN_MANAGER_ADDRESS, address],
    });

    // Get contribution counts
    const contributionCounts = await client.view({
      function: `${CAMPAIGN_MANAGER_ADDRESS}::contribution::get_address_total_contributions`,
      type_arguments: [],
      arguments: [address],
    });

    return {
      campaigns: {
        total: Number(campaignCounts[0]),
        active: Number(campaignCounts[1]),
      },
      contributions: {
        total: Number(contributionCounts[0]),
        verified: Number(contributionCounts[1]),
      },
    };
  } catch (error) {
    console.error('Error fetching activity statistics:', error);
    throw error;
  }
}

async function displayActivityStats(stats: ActivityStats) {
  console.log('\nActivity Statistics:');
  console.log('===================');

  // Campaign Stats
  console.log('\nCampaign Activity:');
  console.log('-----------------');
  console.log(`Total Campaigns Created: ${stats.campaigns.total}`);
  console.log(`Currently Active Campaigns: ${stats.campaigns.active}`);
  console.log(
    `Completed/Inactive Campaigns: ${
      stats.campaigns.total - stats.campaigns.active
    }`
  );
  if (stats.campaigns.total > 0) {
    const activePercentage = (
      (stats.campaigns.active / stats.campaigns.total) *
      100
    ).toFixed(1);
    console.log(`Active Campaign Rate: ${activePercentage}%`);
  }

  // Contribution Stats
  console.log('\nContribution Activity:');
  console.log('---------------------');
  console.log(`Total Contributions Made: ${stats.contributions.total}`);
  console.log(`Verified Contributions: ${stats.contributions.verified}`);
  console.log(
    `Pending/Unverified Contributions: ${
      stats.contributions.total - stats.contributions.verified
    }`
  );
  if (stats.contributions.total > 0) {
    const verificationRate = (
      (stats.contributions.verified / stats.contributions.total) *
      100
    ).toFixed(1);
    console.log(`Contribution Success Rate: ${verificationRate}%`);
  }
}

async function main() {
  try {
    // Initialize Aptos client
    const client = new AptosClient(NODE_URL);

    // Get address from command line or use account's address
    let targetAddress = process.argv[2];

    if (!targetAddress) {
      // If no address provided, try to use the private key from .env
      if (!process.env.PRIVATE_KEY) {
        throw new Error(
          'Please provide an address as argument or set PRIVATE_KEY in .env'
        );
      }
      const account = new AptosAccount(
        HexString.ensure(process.env.PRIVATE_KEY).toUint8Array()
      );
      targetAddress = account.address().hex();
    }

    console.log('Checking activity stats for address:', targetAddress);

    const stats = await getActivityStats(client, targetAddress);
    await displayActivityStats(stats);
  } catch (error) {
    console.error('Error:', error);
    console.log('\nUsage:');
    console.log('npx ts-node scripts/cli/stats/activity.ts [address]');
    console.log(
      'If no address is provided, uses the account from PRIVATE_KEY in .env'
    );
    process.exit(1);
  }
}

main();
