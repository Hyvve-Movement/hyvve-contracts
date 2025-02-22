import { AptosClient, AptosAccount, HexString, Types } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const CAMPAIGN_MANAGER_ADDRESS = process.env.CAMPAIGN_MANAGER_ADDRESS || '';
const NODE_URL = process.env.RPC_URL || '';

async function formatAmount(amount: number): Promise<string> {
  // Convert from Octas to APT (1 APT = 100_000_000 Octas)
  const apt = amount / 100_000_000;
  return `${apt.toFixed(8)} APT (${amount} Octas)`;
}

async function checkAddressStats(client: AptosClient, address: string) {
  try {
    // Get total spent on campaigns
    const totalSpent = await client.view({
      function: `${CAMPAIGN_MANAGER_ADDRESS}::campaign::get_address_total_spent`,
      type_arguments: ['0x1::aptos_coin::AptosCoin'],
      arguments: [CAMPAIGN_MANAGER_ADDRESS, address],
    });

    // Get total earned from contributions
    const totalEarned = await client.view({
      function: `${CAMPAIGN_MANAGER_ADDRESS}::campaign::get_address_total_earned`,
      type_arguments: ['0x1::aptos_coin::AptosCoin'],
      arguments: [CAMPAIGN_MANAGER_ADDRESS, address],
    });

    console.log('\nAddress Statistics:');
    console.log('==================');
    console.log('Address:', address);
    console.log(
      'Total Spent on Campaigns:',
      await formatAmount(Number(totalSpent[0]))
    );
    console.log(
      'Total Earned from Contributions:',
      await formatAmount(Number(totalEarned[0]))
    );

    // Calculate net position
    const netPosition = Number(totalEarned[0]) - Number(totalSpent[0]);
    console.log('Net Position:', await formatAmount(netPosition));
  } catch (error) {
    console.error('Error fetching address statistics:', error);
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

    await checkAddressStats(client, targetAddress);
  } catch (error) {
    console.error('Error:', error);
    console.log('\nUsage:');
    console.log(
      'npx ts-node scripts/cli/stats/check_address_stats.ts [address]'
    );
    console.log(
      'If no address is provided, uses the account from PRIVATE_KEY in .env'
    );
    process.exit(1);
  }
}

main();
