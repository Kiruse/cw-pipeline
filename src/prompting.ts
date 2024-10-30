import { connections, Cosmos, NetworkConfig, networkFromRegistry } from '@apophis-sdk/core';
import { Coin } from '@apophis-sdk/core/types.sdk.js';
import { fromHex } from '@apophis-sdk/core/utils.js';
import { LocalSigner } from '@apophis-sdk/local-signer';
import { confirm, editor, input } from '@inquirer/prompts';
import type { Prompt } from '@inquirer/type';
import { recase } from '@kristiandupont/recase';
import { bech32 } from '@scure/base';
import { Option } from 'commander';
import fs from 'fs/promises';
import * as JsonSchema from 'jsonschema';
import YAML from 'yaml';
import { omit, TMPDIR } from './utils';
import { loadConfig } from './config';

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

export function parseFunds(values: string[]): Coin[] {
  return values.map(value => {
    const [, amount, denom] = value.match(/^(\d+)([a-zA-Z]+)$/) ?? [];
    if (!amount || !denom) throw new Error('Invalid funds format. Must be a list of base coin amounts, e.g. 1untrn, without decimals.');
    return Cosmos.coin(BigInt(amount), denom);
  });
}

export async function getNetworkConfig(options: { network?: string, mainnet?: boolean } = {}): Promise<NetworkConfig> {
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

  const result = await networkFromRegistry(mainnet ? network : `${network}testnet`);

  const cfg = await loadConfig();
  const endpoints = cfg?.[result.name]?.endpoints;
  if (endpoints) {
    if (typeof endpoints.rest === 'string') connections.setRest(result, endpoints.rest);
    if (typeof endpoints.rpc === 'string') connections.setRpc(result, endpoints.rpc);
    if (typeof endpoints.ws === 'string') connections.setWs(result, endpoints.ws);
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
  await fs.mkdir(`${TMPDIR}`, { recursive: true });
  await fs.writeFile(`${TMPDIR}/last-inquire.yml`, YAML.stringify(lastInquire, {indent: 2}));
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

    const envarName = 'CWP_' + recase('mixed', 'screamingSnake')(cfg.name);
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

export function isAddress(input: string) {
  try {
    bech32.decode(input as any);
    return true;
  } catch {
    return false;
  }
}
