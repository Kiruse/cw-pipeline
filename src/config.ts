import { Network, getDataFile, getSecret } from './utils';

export type SecretKey = 'mnemonic';

const DEFAULT_CONFIG: CWPipelineConfig = {
  network: 'testnet',
  secrets: {},
  getSecret: resolveSecret,
};

export interface CWPipelineConfig {
  network: Network;
  secrets: {
    [secret in SecretKey]?: string;
  };

  getSecret(key: SecretKey): Promise<string>;
}

export async function loadConfig(): Promise<CWPipelineConfig> {
  try {
    return normalizeConfig(await getDataFile('config.yaml'));
  } catch {
    return normalizeConfig(DEFAULT_CONFIG);
  }
}

export function normalizeConfig(config: any): CWPipelineConfig {
  config.network = config.network || 'testnet';
  if (!['mainnet', 'testnet'].includes(config.network))
    throw Error('network is required');

  if (!config.secrets)
    config.secrets = {};
  config.getSecret = resolveSecret;

  return config;
}

function resolveSecret(this: CWPipelineConfig, key: SecretKey): Promise<string> {
  if (this.secrets[key])
    return Promise.resolve(this.secrets[key]!);
  return getSecret(key);
}
