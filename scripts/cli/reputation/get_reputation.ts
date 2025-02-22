import { AptosClient, AptosAccount, HexString } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const CAMPAIGN_MANAGER_ADDRESS = process.env.CAMPAIGN_MANAGER_ADDRESS || '';
const NODE_URL = process.env.RPC_URL || '';

interface Badge {
  badge_type: number;
  timestamp: string | number;
  description: number[];
}

interface ReputationStore {
  reputation_score: number;
  badges: Badge[];
  contribution_count: number;
  successful_payments: number;
}

function getBadgeTypeName(badge_type: number): string {
  switch (badge_type) {
    // Contributor badges
    case 1:
      return 'Active Contributor';
    case 2:
      return 'Top Contributor';
    case 3:
      return 'Expert Contributor';

    // Campaign creator badges
    case 10:
      return 'Campaign Creator';
    case 11:
      return 'Reliable Payer';
    case 12:
      return 'Trusted Creator';
    case 13:
      return 'Expert Creator';

    // Verifier badges
    case 20:
      return 'Verifier';
    case 21:
      return 'Trusted Verifier';
    case 22:
      return 'Expert Verifier';

    // Achievement badges
    case 30:
      return 'First Contribution';
    case 31:
      return 'First Campaign';
    case 32:
      return 'First Verification';

    default:
      return 'Unknown Badge';
  }
}

async function getReputationStore(
  client: AptosClient,
  address: string
): Promise<ReputationStore | null> {
  try {
    // Check if reputation store exists
    const hasStore = await client.view({
      function: `${CAMPAIGN_MANAGER_ADDRESS}::reputation::has_reputation_store`,
      type_arguments: [],
      arguments: [address],
    });

    if (!hasStore[0]) {
      return null;
    }

    // Get reputation score
    const score = await client.view({
      function: `${CAMPAIGN_MANAGER_ADDRESS}::reputation::get_reputation_score`,
      type_arguments: [],
      arguments: [address],
    });

    // Get badges
    const badges = await client.view({
      function: `${CAMPAIGN_MANAGER_ADDRESS}::reputation::get_badges`,
      type_arguments: [],
      arguments: [address],
    });

    // Get contribution count
    const contributionCount = await client.view({
      function: `${CAMPAIGN_MANAGER_ADDRESS}::reputation::get_contribution_count`,
      type_arguments: [],
      arguments: [address],
    });

    // Get successful payments
    const successfulPayments = await client.view({
      function: `${CAMPAIGN_MANAGER_ADDRESS}::reputation::get_successful_payments`,
      type_arguments: [],
      arguments: [address],
    });

    return {
      reputation_score: Number(score[0]),
      badges: badges[0] as Badge[],
      contribution_count: Number(contributionCount[0]),
      successful_payments: Number(successfulPayments[0]),
    };
  } catch (error) {
    console.error('Error fetching reputation store:', error);
    return null;
  }
}

async function displayReputationInfo(
  store: ReputationStore | null,
  address: string
) {
  console.log('\nReputation Information:');
  console.log('======================');
  console.log(`Address: ${address}`);

  if (!store) {
    console.log('No reputation store found for this address.');
    return;
  }

  console.log(`Reputation Score: ${store.reputation_score}`);

  // Display earned badges
  console.log('\nEarned Badges:');
  console.log('=============');
  if (store.badges.length === 0) {
    console.log('No badges earned yet');
  } else {
    store.badges.forEach((badge: Badge) => {
      const badgeName = getBadgeTypeName(badge.badge_type);
      const date = new Date(Number(badge.timestamp) * 1000);
      console.log(`${badgeName} - Earned on ${date.toLocaleDateString()}`);
    });
  }

  // Display badge thresholds and progress
  const thresholds = {
    'Bronze (Active Contributor)': 100,
    'Silver (Reliable Participant)': 500,
    'Gold (Top Contributor)': 1000,
    'Platinum (Expert)': 5000,
  };

  console.log('\nBadge Progress:');
  console.log('==============');
  for (const [badge, threshold] of Object.entries(thresholds)) {
    const progress = Math.min((store.reputation_score / threshold) * 100, 100);
    const progressBar = createProgressBar(progress);
    console.log(`${badge}: ${progressBar} ${progress.toFixed(1)}%`);
  }

  console.log('\nActivity Metrics:');
  console.log('================');
  console.log(`Total Contributions: ${store.contribution_count}`);
  console.log(`Successful Payments: ${store.successful_payments}`);
}

function createProgressBar(percentage: number): string {
  const width = 20;
  const filled = Math.floor((percentage / 100) * width);
  const empty = width - filled;
  return '[' + '='.repeat(filled) + ' '.repeat(empty) + ']';
}

async function main() {
  try {
    const client = new AptosClient(NODE_URL);

    // Parse command line arguments or use default
    const address = process.argv[2] || CAMPAIGN_MANAGER_ADDRESS;

    if (!address) {
      throw new Error(
        'No address provided and CAMPAIGN_MANAGER_ADDRESS not set in .env'
      );
    }

    // Get reputation information
    const reputationStore = await getReputationStore(client, address);

    // Display results
    await displayReputationInfo(reputationStore, address);
  } catch (error) {
    console.error('Error:', error);
    console.log('\nUsage:');
    console.log(
      'npx ts-node scripts/cli/reputation/get_reputation.ts [address]'
    );
    console.log(
      '- Optionally provide an address to view reputation information'
    );
    console.log(
      '- If no address is provided, uses CAMPAIGN_MANAGER_ADDRESS from .env'
    );
    process.exit(1);
  }
}

main();
