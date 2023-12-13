import { MnemonicKey } from '@terra-money/feather.js/src';
import { Network, getDataFile, getSecret } from './utils';

export type SecretKey = 'mnemonic';

const DEFAULT_CONFIG: CWPipelineConfig = {
  network: 'testnet',
  secrets: {},
  getSecret: resolveSecret,
  getMnemonicKey: getMnemonicKey,
};

export interface CWPipelineConfig {
  network: Network;
  secrets: {
    [secret in SecretKey]?: string;
  };

  getSecret(key: SecretKey): Promise<string>;
  getMnemonicKey(): Promise<MnemonicKey>;
}

export async function loadConfig(options: { network: Network }): Promise<CWPipelineConfig> {
  let result: any;
  try {
    result = normalizeConfig(await getDataFile('config.yaml'));
  } catch {
    result = normalizeConfig(DEFAULT_CONFIG);
  }
  if (options.network) result.network = options.network;
  return result;
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

async function getMnemonicKey(this: CWPipelineConfig): Promise<MnemonicKey> {
  const mnemonic = await this.getSecret('mnemonic');
  // TODO: distinguish coin type based on network
  return new MnemonicKey({ mnemonic });
}
