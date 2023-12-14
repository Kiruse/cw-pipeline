import { MnemonicKey } from '@terra-money/feather.js/src';
import fs from 'fs/promises';
import YAML from 'yaml';
import { DATADIR, Network, getSecret } from './utils';

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
  const local = await tryReadConfig('.cw-pipeline.yml');
  const user  = await tryReadConfig(`${DATADIR}/config.yml`);
  const result = normalizeConfig({
    ...DEFAULT_CONFIG,
    ...user,
    ...local,
  });
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

async function tryReadConfig(filepath: string) {
  try {
    return YAML.parse(await fs.readFile(filepath, 'utf8'));
  } catch {
    return {};
  }
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
