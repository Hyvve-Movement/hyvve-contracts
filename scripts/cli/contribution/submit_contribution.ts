import {
  AptosClient,
  AptosAccount,
  HexString,
  TxnBuilderTypes,
  BCS,
} from 'aptos';
import dotenv from 'dotenv';
import crypto from 'crypto';

dotenv.config();

const NODE_URL = process.env.RPC_URL || '';

async function main() {
  try {
    // Initialize Aptos client
    const client = new AptosClient(NODE_URL);

    // Initialize contributor account
    if (!process.env.PRIVATE_KEY) {
      throw new Error('Private key not found in .env file');
    }
    const contributorAccount = new AptosAccount(
      HexString.ensure(process.env.PRIVATE_KEY).toUint8Array()
    );

    // Initialize verifier account for signing
    if (!process.env.VERIFIER_PRIVATE_KEY) {
      throw new Error('Verifier private key not found in .env file');
    }
    const verifierAccount = new AptosAccount(
      HexString.ensure(process.env.VERIFIER_PRIVATE_KEY).toUint8Array()
    );

    // Get required parameters from command line arguments
    const [campaignId, dataUrl, qualityScore] = process.argv.slice(2);
    if (!campaignId || !dataUrl || !qualityScore) {
      console.error('Missing required parameters');
      console.log(
        'Usage: npx ts-node scripts/cli/contribution/submit_contribution.ts <campaign_id> <data_url> <quality_score>'
      );
      process.exit(1);
    }

    // Generate a unique contribution ID
    const contributionId = `contribution_${Date.now()}_${crypto
      .randomBytes(4)
      .toString('hex')}`;

    // Calculate data hash (using SHA-256 of the data URL)
    const dataHash = Array.from(
      crypto.createHash('sha256').update(dataUrl).digest()
    );

    console.log('Debug Info:');
    console.log('Campaign ID bytes:', Array.from(Buffer.from(campaignId)));
    console.log('Data Hash:', dataHash);
    console.log('Data URL bytes:', Array.from(Buffer.from(dataUrl)));

    // Create BCS serializer
    const serializer = new BCS.Serializer();
    serializer.serializeU64(parseInt(qualityScore));
    const bcsQualityScore = serializer.getBytes();
    console.log('BCS Quality Score:', Array.from(bcsQualityScore));

    // Create message to sign (concatenate all required fields)
    const messageToSign = Buffer.concat([
      Buffer.from(campaignId, 'utf8'), // campaign_id
      Buffer.from(dataHash), // data_hash
      Buffer.from(dataUrl, 'utf8'), // data_url
      bcsQualityScore, // BCS encoded quality_score
    ]);

    console.log('Message to sign:', Array.from(messageToSign));
    console.log('Verifier address:', verifierAccount.address().hex());

    // Hash the message with SHA-256 before signing
    const messageHash = crypto
      .createHash('sha2-256')
      .update(messageToSign)
      .digest();
    console.log('Message hash:', Array.from(messageHash));

    // Sign the hashed message with verifier's key
    const signature = verifierAccount.signBuffer(messageHash).toUint8Array();
    console.log('Signature:', Array.from(signature));

    // Also log the public key we're using
    console.log(
      'Verifier public key:',
      Array.from(verifierAccount.pubKey().toUint8Array())
    );

    console.log('\nSubmitting contribution...');
    console.log('Campaign ID:', campaignId);
    console.log('Contribution ID:', contributionId);
    console.log('Data URL:', dataUrl);
    console.log('Quality Score:', qualityScore);

    // Create payload
    const payload = {
      type: 'entry_function_payload',
      function: `${process.env.CAMPAIGN_MANAGER_ADDRESS}::contribution::submit_contribution`,
      type_arguments: ['0x1::aptos_coin::AptosCoin'],
      arguments: [
        campaignId,
        contributionId,
        dataUrl,
        dataHash,
        Array.from(signature),
        parseInt(qualityScore),
      ],
    };

    // Submit transaction using contributor's account
    const txnRequest = await client.generateTransaction(
      contributorAccount.address(),
      payload
    );
    const signedTxn = await client.signTransaction(
      contributorAccount,
      txnRequest
    );
    const txnResult = await client.submitTransaction(signedTxn);

    console.log('Transaction submitted!');
    console.log('Transaction hash:', txnResult.hash);

    // Wait for transaction
    await client.waitForTransaction(txnResult.hash);
    console.log('Transaction successful!');
    console.log(
      'View on explorer:',
      `https://explorer.aptoslabs.com/txn/${txnResult.hash}?network=testnet`
    );

    // Display contribution details
    console.log('\nContribution submitted successfully:');
    console.log('Contribution ID:', contributionId);
    console.log('Campaign ID:', campaignId);
    console.log('Data URL:', dataUrl);
    console.log('Quality Score:', qualityScore);
  } catch (error) {
    console.error('Error submitting contribution:', error);
    process.exit(1);
  }
}

main();
