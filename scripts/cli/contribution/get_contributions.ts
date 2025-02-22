import { AptosClient, AptosAccount, HexString } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const CAMPAIGN_MANAGER_ADDRESS = process.env.CAMPAIGN_MANAGER_ADDRESS || '';
const NODE_URL = process.env.RPC_URL || '';

interface Contribution {
  contribution_id: string;
  campaign_id: string;
  contributor: string;
  data_url: string;
  data_hash: number[];
  timestamp: string | number;
  verification_scores: {
    verifier_reputation: number;
    quality_score: number;
  };
  is_verified: boolean;
  reward_released: boolean;
}

async function formatAmount(amount: number): Promise<string> {
  const apt = amount / 100_000_000;
  return `${apt.toFixed(8)} APT (${amount} Octas)`;
}

async function getCampaignDetails(client: AptosClient, campaignId: string) {
  try {
    const details = await client.view({
      function: `${CAMPAIGN_MANAGER_ADDRESS}::campaign::get_campaign_details`,
      type_arguments: [],
      arguments: [CAMPAIGN_MANAGER_ADDRESS, campaignId],
    });

    return {
      title: details[0],
      description: details[1],
      requirements: details[2],
      criteria: details[3],
      unitPrice: Number(details[4]),
      totalBudget: Number(details[5]),
      minDataCount: Number(details[6]),
      maxDataCount: Number(details[7]),
      expiration: Number(details[8]),
      isActive: details[9],
      metadataUri: details[10],
    };
  } catch (error) {
    console.error('Error fetching campaign details:', error);
    return null;
  }
}

async function getContributions(
  client: AptosClient,
  campaignId?: string,
  contributorAddress?: string
) {
  try {
    // Get contribution store
    const contributionStore = await client.view({
      function: `${CAMPAIGN_MANAGER_ADDRESS}::contribution::get_contribution_store`,
      type_arguments: [],
      arguments: [],
    });

    let contributions = contributionStore[0] as Contribution[];

    // Filter by campaign ID if provided
    if (campaignId) {
      contributions = contributions.filter((c) => c.campaign_id === campaignId);
    }

    // Filter by contributor address if provided
    if (contributorAddress) {
      contributions = contributions.filter(
        (c) => c.contributor === contributorAddress
      );
    }

    return contributions;
  } catch (error) {
    console.error('Error fetching contributions:', error);
    return [];
  }
}

async function displayContributions(
  client: AptosClient,
  contributions: Contribution[],
  showCampaignDetails: boolean = false
) {
  console.log(`\nFound ${contributions.length} contributions:`);

  if (contributions.length === 0) {
    return;
  }

  // Get campaign details if needed
  const campaignDetails = showCampaignDetails
    ? await getCampaignDetails(client, contributions[0].campaign_id)
    : null;

  if (showCampaignDetails && campaignDetails) {
    console.log('\nCampaign Details:');
    console.log('=================');
    console.log(`Title: ${campaignDetails.title}`);
    console.log(`Description: ${campaignDetails.description}`);
    console.log(`Requirements: ${campaignDetails.requirements}`);
    console.log(`Unit Price: ${await formatAmount(campaignDetails.unitPrice)}`);
    console.log(
      `Total Budget: ${await formatAmount(campaignDetails.totalBudget)}`
    );
    console.log(
      `Data Points: ${campaignDetails.minDataCount} - ${campaignDetails.maxDataCount}`
    );
    console.log(`Status: ${campaignDetails.isActive ? 'Active' : 'Inactive'}`);
    console.log(
      `Expires: ${new Date(
        Number(campaignDetails.expiration) * 1000
      ).toLocaleString()}`
    );
    console.log('\nContributions:');
    console.log('==============');
  }

  for (const contribution of contributions) {
    console.log('\n-------------------');
    console.log(`Contribution ID: ${contribution.contribution_id}`);
    console.log(`Campaign ID: ${contribution.campaign_id}`);
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

    if (contribution.verification_scores) {
      console.log('Verification Scores:');
      console.log(
        `  - Verifier Reputation: ${contribution.verification_scores.verifier_reputation}`
      );
      console.log(
        `  - Quality Score: ${contribution.verification_scores.quality_score}`
      );
    }

    console.log(
      `Reward Status: ${contribution.reward_released ? 'Released' : 'Pending'}`
    );
  }
}

async function main() {
  try {
    const client = new AptosClient(NODE_URL);

    // Parse command line arguments
    const campaignId = process.argv[2];
    const contributorAddress = process.argv[3];

    if (!campaignId && !contributorAddress) {
      throw new Error(
        'Please provide either a campaign ID or contributor address'
      );
    }

    // Get contributions
    const contributions = await getContributions(
      client,
      campaignId,
      contributorAddress
    );

    // Display results
    if (campaignId && !contributorAddress) {
      // If only campaign ID provided, show campaign details
      await displayContributions(client, contributions, true);
    } else {
      // If filtering by contributor or both, don't show campaign details
      await displayContributions(client, contributions, false);
    }

    // Show summary statistics
    console.log('\nSummary Statistics:');
    console.log('==================');
    console.log(`Total Contributions: ${contributions.length}`);
    const verifiedCount = contributions.filter((c) => c.is_verified).length;
    const rewardedCount = contributions.filter((c) => c.reward_released).length;
    console.log(`Verified Contributions: ${verifiedCount}`);
    console.log(`Rewards Released: ${rewardedCount}`);

    if (contributions.length > 0) {
      const verificationRate = (
        (verifiedCount / contributions.length) *
        100
      ).toFixed(1);
      const rewardRate = ((rewardedCount / contributions.length) * 100).toFixed(
        1
      );
      console.log(`Verification Rate: ${verificationRate}%`);
      console.log(`Reward Release Rate: ${rewardRate}%`);
    }
  } catch (error) {
    console.error('Error:', error);
    console.log('\nUsage:');
    console.log(
      'npx ts-node scripts/cli/contribution/get_contributions.ts [campaign_id] [contributor_address]'
    );
    console.log(
      '- Provide campaign_id to view all contributions for a campaign'
    );
    console.log(
      '- Provide contributor_address to view all contributions by an address'
    );
    console.log(
      '- Provide both to filter contributions by campaign and contributor'
    );
    process.exit(1);
  }
}

main();
