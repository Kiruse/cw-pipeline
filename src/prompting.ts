import { Asset, NetworkConfig } from '@apophis-sdk/core';
import { fromHex } from '@apophis-sdk/core/utils.js';
import { LocalSigner } from '@apophis-sdk/local-signer';
import { ChainRegistryClient } from '@chain-registry/client';
import { confirm, input } from '@inquirer/prompts';
import type { Prompt } from '@inquirer/type';
import { Option } from 'commander';
import fs from 'fs/promises';
import * as JsonSchema from 'jsonschema';
import YAML from 'yaml';
import { omit, TMPDIR } from './utils';
import { recase } from '@kristiandupont/recase';

type PromptValue<P extends Prompt<any, any>> = P extends Prompt<infer T, any> ? T : never;
type PromptConfig<P extends Prompt<any, any>> = P extends Prompt<any, infer T> ? T : never;

export const NetworkOption = (flags = '-n, --network') =>
  new Option(
    `${flags} <network>`,
    'Network name corresponding to the chain registry to operate on.',
  );

export const MainnetOption = (flags = '--mainnet') =>
  new Option(flags, 'Whether to use mainnet.');

export async function getNetworkConfig(options: { network?: string, mainnet?: boolean } = {}): Promise<NetworkConfig> {
  const network = await inquire(input, {
    name: 'network',
    message: 'Network name as defined in the chain registry',
    default: 'neutron',
    validate: (input: string) => input?.trim().length > 0,
  });

  const mainnet = await inquire(confirm, {
    name: 'mainnet',
    message: 'Use mainnet?',
    default: false,
  }, options);

  const chainName = mainnet ? network : `testnets/${network}testnet`;
  const client = new ChainRegistryClient({ chainNames: [chainName] });
  await client.fetchUrls();

  const chain = client.getChain(chainName.replace('testnets/', ''));
  const assets = client.getChainAssetList(chainName.replace('testnets/', ''));
  const feeToken = chain.fees?.fee_tokens?.[0];
  const feeAssetRaw = assets.assets.find(asset => asset.base === feeToken?.denom);
  if (!feeToken || !feeAssetRaw) throw new Error(`No fee asset found for ${chainName}`);

  const feeAsset: Asset = {
    denom: feeAssetRaw.base,
    name: feeAssetRaw.symbol,
    decimals: feeAssetRaw.denom_units.find(unit => unit.denom === feeAssetRaw.display)?.exponent ?? 0,
  };

  if (!feeToken.average_gas_price) throw new Error(`No average gas price found for ${chainName}`);

  const result: NetworkConfig = {
    name: chainName,
    chainId: chain.chain_id!,
    addressPrefix: chain.bech32_prefix!,
    prettyName: chain.pretty_name!,
    assets: [feeAsset],
    gas: [{
      asset: feeAsset,
      avgPrice: feeToken.average_gas_price,
      lowPrice: feeToken.low_gas_price ?? feeToken.average_gas_price,
      highPrice: feeToken.high_gas_price ?? feeToken.average_gas_price,
      minFee: feeToken.fixed_min_gas_price,
    }],
    slip44: chain.slip44,
  };

  if (!result.chainId || !result.addressPrefix)
    throw new Error(`Failed to get chain data for ${chainName}`);

  return result;
}

export async function getSigner(): Promise<LocalSigner> {
  if (!process.env.CWP_PRIVATE_KEY && !process.env.CWP_MNEMONIC) {
    console.error('Please supply either a private key or a mnemonic via environment variables. ' +
      'In a local environment, please take care to store these in an encrypted keyring.');
    process.exit(1);
  }
  let signer: LocalSigner;
  if (process.env.CWP_PRIVATE_KEY)
    signer = LocalSigner.fromPrivateKey(fromHex(process.env.CWP_PRIVATE_KEY))
  else
    signer = await LocalSigner.fromMnemonic(process.env.CWP_MNEMONIC!);
  return signer;
}

export async function validateJson(msg: any, schemaPath: string): Promise<void> {
  const schema = JSON.parse(await fs.readFile(schemaPath, 'utf8'));
  const results = JsonSchema.validate(msg, schema);
  if (!results.valid) {
    console.error('Invalid JSON:');
    console.error(YAML.stringify(
      results.errors.map(err => omit(err, 'schema')),
      { indent: 2 },
    ));
    process.exit(1);
  }
}

export const validateInitMsg = (msg: any) => validateJson(msg, 'schema/raw/instantiate.json');
export const validateExecuteMsg = (msg: any) => validateJson(msg, 'schema/raw/execute.json');
export const validateQueryMsg = (msg: any) => validateJson(msg, 'schema/raw/query.json');

var lastInquire: any;
async function getLastInquire(name: string, defaultValue?: string): Promise<string | undefined> {
  if (!lastInquire) {
    try {
      lastInquire = YAML.parse(await fs.readFile(`${TMPDIR}/last-inquire.yml`, 'utf8'));
    } catch {
      lastInquire = {};
    }
  }

  if (name in lastInquire) return lastInquire[name];
  return lastInquire[name] = defaultValue;
}

async function saveLastInquire(key: string, value: any) {
  lastInquire[key] = value;
  await fs.writeFile(`${TMPDIR}/last-inquire.yml`, YAML.stringify(lastInquire, {indent: 2}));
}

/** Inquirer wrapper that supports commander options. Any options provided or answers found in the
 * environment variables will skip the corresponding question. Environment variables are queried
 * by converting to SHOUT_CASE aka SCREAMING_SNAKE_CASE & prefixed with `CWP_`.
 */
export async function inquire<P extends Prompt<any, any>>(
  prompt: P,
  promptConfig: PromptConfig<P> & { name?: string },
  options: Record<string, any> = {},
): Promise<PromptValue<P>> {
  const cfg: any = promptConfig;

  if (cfg.name) {
    if (options[cfg.name]) return options[cfg.name];

    const envarName = recase('mixed', 'screamingSnake')(cfg.name);
    if (process.env[`CWP_${envarName}`])
      //@ts-ignore
      return process.env[`CWP_${envarName}`];
  }

  const lastInquire = cfg.name ? await getLastInquire(cfg.name) : undefined;
  const defaultValue = typeof cfg.default === 'function' ? await cfg.default() : cfg.default;

  const result = await prompt({
    ...promptConfig,
    //@ts-ignore
    default: lastInquire ?? defaultValue,
  });

  if (cfg.name) await saveLastInquire(cfg.name, result);
  return result;
}
