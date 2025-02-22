import { AptosClient, AptosAccount, HexString, Types } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const NODE_URL = process.env.RPC_URL || '';

interface VerifierInfo {
  address: string;
  public_key: string;
  reputation_score: number;
  total_verifications: number;
  is_active: boolean;
  last_active: number;
}

interface VerifierRegistry {
  verifiers: VerifierInfo[];
  admin: string;
}

interface VerifierStore {
  admin: string;
  verifier_keys: {
    public_key: string;
    reputation_score: number;
    total_verifications: number;
    last_active: number;
  }[];
}

async function main() {
  try {
    const client = new AptosClient(NODE_URL);

    // Get verifier account
    if (!process.env.VERIFIER_PRIVATE_KEY) {
      throw new Error('Verifier private key not found in .env file');
    }
    const verifierAccount = new AptosAccount(
      HexString.ensure(process.env.VERIFIER_PRIVATE_KEY).toUint8Array()
    );

    // Ensure CAMPAIGN_MANAGER_ADDRESS is defined
    if (!process.env.CAMPAIGN_MANAGER_ADDRESS) {
      throw new Error('Campaign manager address not found in .env file');
    }
    const campaignManagerAddress = process.env.CAMPAIGN_MANAGER_ADDRESS;

    console.log('Checking verifier registration...');
    console.log('Verifier address:', verifierAccount.address().hex());
    console.log('Verifier public key:', verifierAccount.pubKey().hex());

    // Check if verifier registry exists
    const resources = await client.getAccountResources(
      HexString.ensure(campaignManagerAddress)
    );

    const verifierRegistry = resources.find(
      (r) => r.type === `${campaignManagerAddress}::verifier::VerifierRegistry`
    ) as (Types.MoveResource & { data: VerifierRegistry }) | undefined;

    const verifierStore = resources.find(
      (r) => r.type === `${campaignManagerAddress}::verifier::VerifierStore`
    ) as (Types.MoveResource & { data: VerifierStore }) | undefined;

    console.log('\nChecking contract state:');
    if (verifierRegistry) {
      console.log('\nVerifier Registry found:');
      console.log(JSON.stringify(verifierRegistry.data, null, 2));
    } else {
      console.log('Verifier Registry not found!');
    }

    if (verifierStore) {
      console.log('\nVerifier Store found:');
      console.log(JSON.stringify(verifierStore.data, null, 2));
    } else {
      console.log('Verifier Store not found!');
    }

    // Check if this verifier is registered
    if (verifierRegistry?.data?.verifiers) {
      const verifiers = verifierRegistry.data.verifiers;
      const verifierInfo = verifiers.find(
        (v) => v.address === verifierAccount.address().hex()
      );

      if (verifierInfo) {
        console.log('\nVerifier Status:');
        console.log('----------------');
        console.log('Registration: Registered');
        console.log(`Reputation Score: ${verifierInfo.reputation_score}`);
        console.log(`Total Verifications: ${verifierInfo.total_verifications}`);
        console.log(`Active: ${verifierInfo.is_active ? 'Yes' : 'No'}`);
        console.log(
          `Last Active: ${new Date(
            verifierInfo.last_active * 1000
          ).toLocaleString()}`
        );
      } else {
        console.log('\nVerifier Status: Not registered');
      }

      // Also check verifier store for key registration
      if (verifierStore?.data?.verifier_keys) {
        const verifierKey = verifierStore.data.verifier_keys.find(
          (k) =>
            k.public_key.toLowerCase() ===
            verifierAccount.pubKey().hex().toLowerCase()
        );

        if (verifierKey) {
          console.log('\nVerifier Key Status:');
          console.log('-------------------');
          console.log('Registration: Registered');
          console.log(`Reputation Score: ${verifierKey.reputation_score}`);
          console.log(
            `Total Verifications: ${verifierKey.total_verifications}`
          );
          console.log(
            `Last Active: ${new Date(
              verifierKey.last_active * 1000
            ).toLocaleString()}`
          );
        } else {
          console.log('\nVerifier Key Status: Not registered');
        }
      }
    } else {
      console.log('\nNo verifiers found in registry');
    }
  } catch (error) {
    console.error('Error checking verifier:', error);
    process.exit(1);
  }
}

main();
