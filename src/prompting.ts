import { type CosmosNetworkConfig } from '@apophis-sdk/core';
import { Coin } from '@apophis-sdk/core/types.sdk.js';
import { fromHex } from '@apophis-sdk/core/utils.js';
import { Cosmos } from '@apophis-sdk/cosmos';
import { LocalSigner } from '@apophis-sdk/cosmos/local-signer.js';
import { confirm, editor, input, select } from '@inquirer/prompts';
import type { Prompt } from '@inquirer/type';
import { bech32 } from '@scure/base';
import { snakeCase } from 'case-anything';
import { Option } from 'commander';
import fs from 'fs/promises';
import * as JsonSchema from 'jsonschema';
import path from 'path';
import YAML from 'yaml';
import { loadConfig } from './config';
import { Project } from './project';
import { DATADIR, omit } from './utils';

type PromptValue<P extends Prompt<any, any>> = P extends Prompt<infer T, any> ? T : never;
type PromptConfig<P extends Prompt<any, any>> = P extends Prompt<any, infer T> ? T : never;

export const NetworkOption = (flags = '-n, --network') =>
  new Option(
    `${flags} <network>`,
    'Network name corresponding to the chain registry to operate on. You can set this option with the environment variable CWP_NETWORK.',
  );

export const MainnetOption = (flags = '--mainnet') =>
  new Option(flags, 'Whether to use mainnet. You can set this option with the environment variable CWP_MAINNET.')
    .default(['1', 'true'].includes(process.env.CWP_MAINNET!));

export const FundsOption = (flags = '--funds <amounts...>') =>
  new Option(flags, 'Funds to send with the transaction. Defaults to none. Currently requires base denom w/o decimals, e.g. 1untrn.');

export const SequenceOption = (flags = '-s, --sequence <number>') =>
  new Option(flags, 'Sequence number to use for the transaction. Defaults to the sequence number stored on-chain.')
    .argParser((value) => BigInt(value));

export const ContractOption = (flags = '-c, --contract <contract>') =>
  new Option(flags, 'Contract address or name from the deployments config. When omitted, prompted.');

export function parseFunds(values: string[]): Coin[] {
  return values.map(value => {
    const [, amount, denom] = value.match(/^(\d+)([a-zA-Z]+)$/) ?? [];
    if (!amount || !denom) throw new Error('Invalid funds format. Must be a list of base coin amounts, e.g. 1untrn, without decimals.');
    return Cosmos.coin(BigInt(amount), denom);
  });
}

export async function getNetworkConfig(options: { network?: string, mainnet?: boolean } = {}): Promise<CosmosNetworkConfig> {
  const network = await inquire(input, {
    name: 'network',
    message: 'Network name as defined in the chain registry',
    default: 'neutron',
    validate: (input: string) => input?.trim().length > 0,
  }, options);

  const mainnet = await inquire(confirm, {
    name: 'mainnet',
    message: 'Use mainnet?',
    default: false,
  }, options);

  const cfg = await loadConfig();
  const netname = mainnet ? network : `${network}testnet`;

  let result = cfg[netname]?.network;
  if (!result)
    result = await Cosmos.getNetworkFromRegistry(netname);

  const endpoints = cfg[netname]?.endpoints;
  if (endpoints) {
    result.endpoints = {
      rest: [endpoints.rest],
      rpc: [endpoints.rpc],
      ws: [endpoints.ws],
    };
  }

  if (!result.endpoints?.rest?.length || !result.endpoints?.rpc?.length || !result.endpoints?.ws?.length) {
    console.error('Network endpoints missing. Please add them to the config file.');
    process.exit(1);
  }

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

export async function getDeploymentContract(project: Project, value: string) {
  const config = await project.getDeploymentConfig();
  const exactMatch = config.variants.find(c => c === value);
  if (exactMatch) return exactMatch;

  if (!value) {
    const choice = await inquire(select, {
      message: 'Choose a contract',
      choices: config.variants,
    });
    return choice;
  }

  const partialMatches = config.variants.filter(c => c.includes(value));
  if (partialMatches.length === 0) throw new InputError('No matching contract found');

  if (partialMatches.length === 1) {
    const result = await inquire(confirm, {
      message: `Only one match found: ${partialMatches[0]}. Use this?`,
      default: true,
    });
    if (!result) throw new InputError('User rejected closest match');
    console.log('To avoid this prompt in the future you may provide an exact match.')
    return partialMatches[0];
  }

  const choice = await inquire(select, {
    message: 'Choose a contract',
    choices: partialMatches,
  });
  return choice;
}

export async function validateJson(msg: any, schema: JsonSchema.Schema): Promise<void> {
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

var lastInquire: any;
async function getLastInquire(name: string, defaultValue?: string): Promise<string | undefined> {
  if (!lastInquire) {
    try {
      lastInquire = YAML.parse(await fs.readFile(`${DATADIR}/last-inquire.yml`, 'utf8'));
    } catch {
      lastInquire = {};
    }
  }

  if (name in lastInquire) return lastInquire[name];
  return lastInquire[name] = defaultValue;
}

async function saveLastInquire(key: string, value: any) {
  lastInquire[key] = value;
  await fs.mkdir(`${DATADIR}`, { recursive: true });
  await fs.writeFile(`${DATADIR}/last-inquire.yml`, YAML.stringify(lastInquire, {indent: 2}));
}

/** Inquirer wrapper that supports commander options. Any options provided or answers found in the
 * environment variables will skip the corresponding question. Environment variables are queried
 * by converting to SHOUT_CASE aka SCREAMING_SNAKE_CASE & prefixed with `CWP_`.
 */
export async function inquire<P extends Prompt<any, any>>(
  prompt: P,
  promptConfig: PromptConfig<P> & { name?: string, volatile?: boolean, options?: Record<string, any> },
  options?: Record<string, any>,
): Promise<PromptValue<P>> {
  const cfg: any = promptConfig;
  const opts = options ?? promptConfig.options ?? {};

  if (cfg.name) {
    if (opts[cfg.name] !== undefined) return opts[cfg.name];

    const envarName = 'CWP_' + snakeCase(cfg.name).toUpperCase();
    if (envarName in process.env)
      //@ts-ignore
      return process.env[envarName];
  }

  const lastInquire = cfg.name ? await getLastInquire(cfg.name) : undefined;
  const defaultValue = typeof cfg.default === 'function' ? await cfg.default() : cfg.default;

  const result = await prompt({
    ...promptConfig,
    //@ts-ignore
    default: lastInquire ?? defaultValue,
  });

  if (cfg.name && !cfg.volatile) await saveLastInquire(cfg.name, result);
  return result;
}

export async function inquireEditor(
  promptConfig: PromptConfig<typeof editor> & { name?: string, volatile?: boolean, options?: Record<string, any> },
  options?: Record<string, any>,
): Promise<string> {
  process.env.EDITOR ??= 'nano';
  if (process.env.EDITOR === 'code')
    process.env.EDITOR = 'code --wait';
  return await inquire(editor, promptConfig, options);
}

export async function inquireFunds(
  promptConfig: Omit<PromptConfig<typeof input>, 'message'> & { name?: string, volatile?: boolean, options?: Record<string, any>, message?: string },
  options?: Record<string, any>,
): Promise<Coin[]> {
  const s = await inquire(input, {
    ...promptConfig,
    message: promptConfig.message ?? 'Enter funds',
  }, options);
  const splitter = s.includes(',') ? ',' : ' ';
  return parseFunds(s.split(splitter).map(f => f.trim()));
}

export function getContractFromPath(filepath: string) {
  filepath = path.normalize(filepath);
  if (!filepath.includes(path.sep)) return filepath;
  const parts = filepath.split(path.sep);
  if (!parts.includes('artifacts') && !parts.includes('contracts')) throw new Error('Failed to determine contract name from path');
  const name = parts[parts.indexOf('artifacts') + 1] ?? parts[parts.indexOf('contracts') + 1];
  if (!name) throw new Error('Failed to determine contract name from path');
  return name.replace(/\.wasm$/, '');
}

export function isAddress(input: string) {
  try {
    bech32.decode(input as any);
    return true;
  } catch {
    return false;
  }
}

export class InputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InputError';
  }
}
