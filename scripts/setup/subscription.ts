import { AptosClient, AptosAccount, HexString } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const CAMPAIGN_MANAGER_ADDRESS = process.env.CAMPAIGN_MANAGER_ADDRESS || '';
const NODE_URL = process.env.RPC_URL || '';

async function createSubscription(
  client: AptosClient,
  account: AptosAccount,
  subscriptionType: string,
  autoRenew: boolean
) {
  const payload = {
    type: 'entry_function_payload',
    function: `${CAMPAIGN_MANAGER_ADDRESS}::subscription::create_subscription`,
    type_arguments: ['0x1::aptos_coin::AptosCoin'],
    arguments: [subscriptionType, autoRenew],
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
  console.log('Subscription created successfully! (Price: 2 APT)');
  console.log(
    'View on explorer:',
    `https://explorer.aptoslabs.com/txn/${txnResult.hash}?network=testnet`
  );
}

async function createSubscriptionWithDelegation(
  client: AptosClient,
  account: AptosAccount,
  subscriptionType: string,
  autoRenew: boolean,
  delegationAmount: number
) {
  const payload = {
    type: 'entry_function_payload',
    function: `${CAMPAIGN_MANAGER_ADDRESS}::subscription::create_subscription_with_delegation`,
    type_arguments: ['0x1::aptos_coin::AptosCoin'],
    arguments: [subscriptionType, autoRenew, delegationAmount],
  };

  const txnRequest = await client.generateTransaction(
    account.address(),
    payload
  );
  const signedTxn = await client.signTransaction(account, txnRequest);
  const txnResult = await client.submitTransaction(signedTxn);

  console.log('Creating subscription with delegation...');
  console.log('Transaction hash:', txnResult.hash);
  await client.waitForTransaction(txnResult.hash);
  console.log(
    'Subscription created successfully with delegation! (Price: 2 MOVE)'
  );
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
      autoRenew: result[3],
    });
  } catch (error) {
    console.log('No active subscription found');
  }
}

async function processDueRenewals(client: AptosClient, account: AptosAccount) {
  const payload = {
    type: 'entry_function_payload',
    function: `${CAMPAIGN_MANAGER_ADDRESS}::subscription::process_due_renewals`,
    type_arguments: ['0x1::aptos_coin::AptosCoin'],
    arguments: [],
  };

  const txnRequest = await client.generateTransaction(
    account.address(),
    payload
  );
  const signedTxn = await client.signTransaction(account, txnRequest);
  const txnResult = await client.submitTransaction(signedTxn);

  console.log('Processing due subscription renewals...');
  console.log('Transaction hash:', txnResult.hash);
  await client.waitForTransaction(txnResult.hash);
  console.log('Due subscriptions processed successfully!');
  console.log(
    'View on explorer:',
    `https://explorer.aptoslabs.com/txn/${txnResult.hash}?network=testnet`
  );
}

async function getDueRenewalsCount(client: AptosClient) {
  try {
    const payload = {
      function: `${CAMPAIGN_MANAGER_ADDRESS}::subscription::get_due_renewals_count`,
      type_arguments: [],
      arguments: [],
    };

    const result = await client.view(payload);
    console.log('Due Renewals Count:', result[0]);
    return Number(result[0]);
  } catch (error) {
    console.log('Error getting due renewals count:', error);
    return 0;
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
        const autoRenew = process.argv[4] === 'true';
        await createSubscription(client, account, subscriptionType, autoRenew);
        break;

      case 'create-with-delegation':
        const subType = process.argv[3] || 'premium';
        const autoRenewWithDel = process.argv[4] === 'true';
        const delegationAmount = parseInt(process.argv[5] || '200000000'); // Default 2 APT (enough for 1 renewal)
        await createSubscriptionWithDelegation(
          client,
          account,
          subType,
          autoRenewWithDel,
          delegationAmount
        );
        break;

      case 'renew':
        await renewSubscription(client, account);
        break;

      case 'cancel':
        await cancelSubscription(client, account);
        break;

      case 'setup-payment':
        const amount = parseInt(process.argv[3] || '200000000'); // Default 2 APT (enough for 1 renewal)
        await setupPaymentDelegation(client, account, amount);
        break;

      case 'status':
        await checkSubscriptionStatus(client, account.address().hex());
        break;

      case 'process-renewals':
        await processDueRenewals(client, account);
        break;

      case 'due-count':
        await getDueRenewalsCount(client);
        break;

      default:
        console.log('Invalid command. Available commands:');
        console.log('- create [type] [autoRenew]');
        console.log(
          '- create-with-delegation [type] [autoRenew] [delegationAmount]'
        );
        console.log('- renew');
        console.log('- cancel');
        console.log('- setup-payment [amount]');
        console.log('- status');
        console.log('- process-renewals');
        console.log('- due-count');
    }
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

main();
