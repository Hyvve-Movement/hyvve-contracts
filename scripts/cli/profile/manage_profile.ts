import { AptosClient, AptosAccount, HexString } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const CAMPAIGN_MANAGER_ADDRESS = process.env.CAMPAIGN_MANAGER_ADDRESS || '';
const NODE_URL = process.env.RPC_URL || '';

interface ProfileInfo {
  username: string;
  editCount: number;
}

async function getProfileInfo(
  client: AptosClient,
  address: string
): Promise<ProfileInfo | null> {
  try {
    const usernameResult = await client.view({
      function: `${CAMPAIGN_MANAGER_ADDRESS}::campaign::get_username`,
      type_arguments: [],
      arguments: [address],
    });

    const editCountResult = await client.view({
      function: `${CAMPAIGN_MANAGER_ADDRESS}::campaign::get_username_edit_count`,
      type_arguments: [],
      arguments: [address],
    });

    const usernameBytes = usernameResult[0] as number[];
    let usernameStr = 'No username set';

    try {
      if (usernameBytes && usernameBytes.length > 0) {
        // If the username starts with '0x', it's a hex string
        const hexStr = Buffer.from(usernameBytes).toString();
        if (hexStr.startsWith('0x')) {
          // Remove '0x' prefix and convert hex to ASCII
          const hex = hexStr.slice(2);
          usernameStr = Buffer.from(hex, 'hex').toString();
        } else {
          // Otherwise, just use the bytes directly
          usernameStr = Buffer.from(usernameBytes).toString();
        }
      }
    } catch (error) {
      console.error('Error converting username bytes:', error);
      usernameStr = 'Error decoding username';
    }

    return {
      username: usernameStr,
      editCount: Number(editCountResult[0]),
    };
  } catch (error) {
    console.error('Error fetching profile info:', error);
    return null;
  }
}

async function setUsername(
  client: AptosClient,
  account: AptosAccount,
  username: string
): Promise<void> {
  try {
    // Convert string to bytes
    const usernameBytes = Array.from(Buffer.from(username, 'utf8'));

    const payload = {
      function: `${CAMPAIGN_MANAGER_ADDRESS}::campaign::set_username`,
      type_arguments: [],
      arguments: [usernameBytes],
    };

    const rawTxn = await client.generateTransaction(account.address(), payload);
    const signedTxn = await client.signTransaction(account, rawTxn);
    const result = await client.submitTransaction(signedTxn);
    await client.waitForTransaction(result.hash);
    console.log('Username set successfully!');
  } catch (error) {
    console.error('Error setting username:', error);
  }
}

async function editUsername(
  client: AptosClient,
  account: AptosAccount,
  newUsername: string
): Promise<void> {
  try {
    // Convert string to bytes
    const usernameBytes = Array.from(Buffer.from(newUsername, 'utf8'));

    const payload = {
      function: `${CAMPAIGN_MANAGER_ADDRESS}::campaign::edit_username`,
      type_arguments: [],
      arguments: [usernameBytes],
    };

    const rawTxn = await client.generateTransaction(account.address(), payload);
    const signedTxn = await client.signTransaction(account, rawTxn);
    const result = await client.submitTransaction(signedTxn);
    await client.waitForTransaction(result.hash);
    console.log('Username edited successfully!');
  } catch (error) {
    console.error('Error editing username:', error);
  }
}

async function displayProfileInfo(info: ProfileInfo | null, address: string) {
  console.log('\nProfile Information:');
  console.log('===================');
  console.log(`Address: ${address}`);

  if (!info) {
    console.log('No profile information found for this address.');
    return;
  }

  console.log(`Username: ${info.username}`);
  console.log(`Username edits used: ${info.editCount}/2`);
  console.log(`Remaining edits: ${2 - info.editCount}`);
}

async function main() {
  try {
    const client = new AptosClient(NODE_URL);

    // Check command line arguments
    const command = process.argv[2];
    const param = process.argv[3];

    if (!command) {
      throw new Error('No command provided');
    }

    if (!CAMPAIGN_MANAGER_ADDRESS) {
      throw new Error('CAMPAIGN_MANAGER_ADDRESS not set in .env');
    }

    switch (command.toLowerCase()) {
      case 'view': {
        // Use provided address or fall back to CAMPAIGN_MANAGER_ADDRESS
        const address = param || CAMPAIGN_MANAGER_ADDRESS;
        const profileInfo = await getProfileInfo(client, address);
        await displayProfileInfo(profileInfo, address);
        break;
      }
      case 'set': {
        if (!param) {
          throw new Error('No username provided');
        }
        if (param.length > 32) {
          throw new Error('Username too long (max 32 characters)');
        }
        const privateKey = process.env.PRIVATE_KEY;
        if (!privateKey) {
          throw new Error('PRIVATE_KEY not set in .env');
        }
        const account = new AptosAccount(
          HexString.ensure(privateKey).toUint8Array()
        );
        await setUsername(client, account, param);
        break;
      }
      case 'edit': {
        if (!param) {
          throw new Error('No username provided');
        }
        if (param.length > 32) {
          throw new Error('Username too long (max 32 characters)');
        }
        const privateKey = process.env.PRIVATE_KEY;
        if (!privateKey) {
          throw new Error('PRIVATE_KEY not set in .env');
        }
        const account = new AptosAccount(
          HexString.ensure(privateKey).toUint8Array()
        );
        await editUsername(client, account, param);
        break;
      }
      default:
        throw new Error('Invalid command');
    }
  } catch (error) {
    console.error('Error:', error);
    console.log('\nUsage:');
    console.log(
      'npx ts-node scripts/cli/profile/manage_profile.ts view [address]'
    );
    console.log(
      'npx ts-node scripts/cli/profile/manage_profile.ts set <username>'
    );
    console.log(
      'npx ts-node scripts/cli/profile/manage_profile.ts edit <username>'
    );
    process.exit(1);
  }
}

main();
