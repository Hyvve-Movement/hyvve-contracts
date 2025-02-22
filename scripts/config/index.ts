import dotenv from 'dotenv';

dotenv.config();

export const CONFIG = {
  CAMPAIGN_MANAGER_ADDRESS: process.env.CAMPAIGN_MANAGER_ADDRESS || '',
  NODE_URL: process.env.RPC_URL || '',
  PRIVATE_KEY: process.env.PRIVATE_KEY || '',
};

export function validateConfig() {
  const missingVars = Object.entries(CONFIG)
    .filter(([_, value]) => !value)
    .map(([key]) => key);

  if (missingVars.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missingVars.join(', ')}`
    );
  }
}
