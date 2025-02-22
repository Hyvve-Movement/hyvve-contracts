import { AptosClient, AptosAccount, HexString } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const CAMPAIGN_MANAGER_ADDRESS = process.env.CAMPAIGN_MANAGER_ADDRESS || '';
const NODE_URL = process.env.RPC_URL || '';

async function createSubscription(
  client: AptosClient,
  account: AptosAccount,
  subscriptionType: string,
  price: number,
  autoRenew: boolean
) {
  const payload = {
    type: 'entry_function_payload',
    function: `${CAMPAIGN_MANAGER_ADDRESS}::subscription::create_subscription`,
    type_arguments: ['0x1::aptos_coin::AptosCoin'],
    arguments: [subscriptionType, price, autoRenew],
  };

  const txnRequest = await client.generateTransaction(
    account.address(),
    payload
  );
  const signedTxn = await client.signTransaction(account, txnRequest);
  const txnResult = await client.submitTransaction(signedTxn);

  console.log('Creating subscription...');
  console.log('Transaction hash:', txnResult.hash);
  await client.waitForTransaction(txnResult.hash);
  console.log('Subscription created successfully!');
  console.log(
    'View on explorer:',
    `https://explorer.aptoslabs.com/txn/${txnResult.hash}?network=testnet`
  );
}

async function renewSubscription(client: AptosClient, account: AptosAccount) {
  const payload = {
    type: 'entry_function_payload',
    function: `${CAMPAIGN_MANAGER_ADDRESS}::subscription::renew_subscription`,
    type_arguments: ['0x1::aptos_coin::AptosCoin'],
    arguments: [],
  };

  const txnRequest = await client.generateTransaction(
    account.address(),
    payload
  );
  const signedTxn = await client.signTransaction(account, txnRequest);
  const txnResult = await client.submitTransaction(signedTxn);

  console.log('Renewing subscription...');
  console.log('Transaction hash:', txnResult.hash);
  await client.waitForTransaction(txnResult.hash);
  console.log('Subscription renewed successfully!');
  console.log(
    'View on explorer:',
    `https://explorer.aptoslabs.com/txn/${txnResult.hash}?network=testnet`
  );
}

async function cancelSubscription(client: AptosClient, account: AptosAccount) {
  const payload = {
    type: 'entry_function_payload',
    function: `${CAMPAIGN_MANAGER_ADDRESS}::subscription::cancel_subscription`,
    type_arguments: [],
    arguments: [],
  };

  const txnRequest = await client.generateTransaction(
    account.address(),
    payload
  );
  const signedTxn = await client.signTransaction(account, txnRequest);
  const txnResult = await client.submitTransaction(signedTxn);

  console.log('Cancelling subscription...');
  console.log('Transaction hash:', txnResult.hash);
  await client.waitForTransaction(txnResult.hash);
  console.log('Subscription cancelled successfully!');
  console.log(
    'View on explorer:',
    `https://explorer.aptoslabs.com/txn/${txnResult.hash}?network=testnet`
  );
}

async function setupPaymentDelegation(
  client: AptosClient,
  account: AptosAccount,
  amount: number
) {
  const payload = {
    type: 'entry_function_payload',
    function: `${CAMPAIGN_MANAGER_ADDRESS}::subscription::setup_payment_delegation`,
    type_arguments: ['0x1::aptos_coin::AptosCoin'],
    arguments: [amount],
  };

  const txnRequest = await client.generateTransaction(
    account.address(),
    payload
  );
  const signedTxn = await client.signTransaction(account, txnRequest);
  const txnResult = await client.submitTransaction(signedTxn);

  console.log('Setting up payment delegation...');
  console.log('Transaction hash:', txnResult.hash);
  await client.waitForTransaction(txnResult.hash);
  console.log('Payment delegation setup successfully!');
  console.log(
    'View on explorer:',
    `https://explorer.aptoslabs.com/txn/${txnResult.hash}?network=testnet`
  );
}

async function checkSubscriptionStatus(client: AptosClient, address: string) {
  try {
    const payload = {
      function: `${CAMPAIGN_MANAGER_ADDRESS}::subscription::get_subscription_status`,
      type_arguments: [],
      arguments: [address],
    };

    const result = await client.view(payload);
    console.log('Subscription Status:', {
      isActive: result[0],
      endTime: new Date(Number(result[1]) * 1000).toLocaleString(),
      subscriptionType: result[2],
    });
  } catch (error) {
    console.log('No active subscription found');
  }
}

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

    // Get command line arguments
    const command = process.argv[2];

    switch (command) {
      case 'create':
        const subscriptionType = process.argv[3] || 'premium';
        const price = parseInt(process.argv[4] || '100000000'); // Default 1 APT
        const autoRenew = process.argv[5] === 'true';
        await createSubscription(
          client,
          account,
          subscriptionType,
          price,
          autoRenew
        );
        break;

      case 'renew':
        await renewSubscription(client, account);
        break;

      case 'cancel':
        await cancelSubscription(client, account);
        break;

      case 'setup-payment':
        const amount = parseInt(process.argv[3] || '100000000'); // Default 1 APT
        await setupPaymentDelegation(client, account, amount);
        break;

      case 'status':
        await checkSubscriptionStatus(client, account.address().hex());
        break;

      default:
        console.log('Invalid command. Available commands:');
        console.log('- create [type] [price] [autoRenew]');
        console.log('- renew');
        console.log('- cancel');
        console.log('- setup-payment [amount]');
        console.log('- status');
    }
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

main();
