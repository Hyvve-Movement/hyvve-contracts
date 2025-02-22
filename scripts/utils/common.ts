import { AptosClient, AptosAccount, HexString, Types } from 'aptos';
import { CONFIG } from '../config';

export async function getAptosClient(): Promise<AptosClient> {
  return new AptosClient(CONFIG.NODE_URL);
}

export async function getAccount(): Promise<AptosAccount> {
  if (!CONFIG.PRIVATE_KEY) {
    throw new Error('PRIVATE_KEY not found in environment');
  }
  return new AptosAccount(HexString.ensure(CONFIG.PRIVATE_KEY).toUint8Array());
}

export async function submitTransaction(
  client: AptosClient,
  account: AptosAccount,
  payload: Types.EntryFunctionPayload
): Promise<string> {
  const txnRequest = await client.generateTransaction(
    account.address(),
    payload
  );
  const signedTxn = await client.signTransaction(account, txnRequest);
  const txnResult = await client.submitTransaction(signedTxn);

  console.log('Transaction submitted. Hash:', txnResult.hash);
  await client.waitForTransaction(txnResult.hash);
  console.log('Transaction successful!');

  return txnResult.hash;
}

export function formatNumber(num: number): string {
  return new Intl.NumberFormat().format(num);
}

export function calculatePercentage(part: number, total: number): string {
  if (total === 0) return '0.0';
  return ((part / total) * 100).toFixed(1);
}
