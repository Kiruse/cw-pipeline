import { LCDClient } from '@terra-money/feather.js/src';
import { Option } from 'commander';
import fs from 'fs/promises'
import * as JsonSchema from 'jsonschema';
import os from 'os'
import YAML from 'yaml';

export type Network = 'mainnet' | 'testnet';
export type Logs = {
  eventsByType: {
    [type: string]: {
      [attr: string]: string[];
    };
  };
  msg_index: number;
  log: string;
  events: {
    type: string;
    attributes: {
      key: string;
      value: string;
    }[];
  }[];
}[];

export const DATADIR = `${os.homedir()}/.cw-pipeline`;

export const getChainID = (network: Network = 'testnet') => network === 'mainnet' ? 'phoenix-1' : 'pisco-1';

export const getLCD = (network: Network = 'testnet') => new LCDClient(
  network === 'mainnet'
  ? {
      'phoenix-1': {
        chainID: 'phoenix-1',
        gasAdjustment: 1.15,
        gasPrices: { uluna: 0.15 },
        lcd: 'https://phoenix-lcd.terra.dev',
        prefix: 'terra',
      },
    }
  : {
      'pisco-1': {
        chainID: 'pisco-1',
        gasAdjustment: 1.15,
        gasPrices: { uluna: 0.15 },
        lcd: 'https://pisco-lcd.terra.dev',
        prefix: 'terra',
      },
    },
);

export async function getSecret(name: string): Promise<string> {
  let secret: string | undefined;
  try {
    secret = await fs.readFile(`${os.homedir()}/.shh/${name}`, 'utf8');
  } catch {}
  if (!secret) {
    try {
      secret = await fs.readFile(`./.shh/${name}`, 'utf8');
    } catch {}
  }
  if (!secret)
    secret = process.env[toShoutCase(name)];
  if (!secret)
    throw Error(`Secret ${name} not found`);
  return secret.trim();
}

export function error(...msgs: any[]): never {
  console.error(...msgs);
  process.exit(1);
}

// simple helper to get more type info into coffeescripts
export const getLogs = (result: any): Logs => result.logs ?? [];

export function getLogTimestamp() {
  const now = new Date(Date.now());
  const year = now.getFullYear();
  const month = `${now.getMonth() + 1}`.padStart(2, '0');
  const day = `${now.getDate()}`.padStart(2, '0');
  const hour = `${now.getHours()}`.padStart(2, '0');
  const minute = `${now.getMinutes()}`.padStart(2, '0');
  const second = `${now.getSeconds()}`.padStart(2, '0');
  return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
}

export const initDataDir = () => fs.mkdir(DATADIR, { recursive: true });
export const getDataFile = (name: string, opts: fs.FileReadOptions = 'utf8') => fs.readFile(`${DATADIR}/${name}`, opts);

export const NetworkOption = (flags = '-n, --network') =>
  new Option(
    `${flags} <network>`,
    'Network to operate on.',
  )
  .choices(['mainnet', 'testnet']);

/** Gets the chain name (+ optional -testnet suffix) for the given network. This should be used to
 * identify the network in a map.
 */
export function getNetwork(option: Network): string {
  switch (option) {
    case 'mainnet':
      return 'terra2';
    case 'testnet':
      return 'terra2-testnet';
  }
}

export function getBechPrefix(option: Network): string {
  switch (option) {
    case 'mainnet':
      return 'terra';
    case 'testnet':
      return 'terra';
  }
}

export async function logResult(result: any, network: Network) {
  await fs.appendFile(
    'cw-pipeline.log',
    `[${getLogTimestamp()} ${getNetwork(network)}]\n` +
    YAML.stringify(result, { indent: 2 }) + '\n\n',
  );
}

export const toShoutCase = (str: string) => str.replace(/([A-Z])/g, '_$1').toUpperCase();

export function omit<T, K extends keyof T>(obj: T, ...keys: K[]): Omit<T, K> {
  const result = { ...obj };
  for (const key of keys)
    delete result[key];
  return result;
}

export async function validateInitMsg(msg: any): Promise<void> {
  const schema = JSON.parse(await fs.readFile('schema/raw/instantiate.json', 'utf8'));
  const results = JsonSchema.validate(msg, schema);
  if (!results.valid) {
    console.error('Your instantiate message failed validation:');
    console.error(YAML.stringify(
      results.errors.map(err => omit(err, 'schema')),
      { indent: 2 }
    ));
    process.exit(1);
  }
}

export async function validateExecuteMsg(msg: any): Promise<void> {
  const schema = JSON.parse(await fs.readFile('schema/raw/execute.json', 'utf8'));
  const results = JsonSchema.validate(msg, schema);
  if (!results.valid) {
    console.error('Your execute message failed validation:');
    console.error(YAML.stringify(
      results.errors.map(err => omit(err, 'schema')),
      { indent: 2 }
    ));
    process.exit(1);
  }
}

export async function validateQueryMsg(msg: any): Promise<void> {
  const schema = JSON.parse(await fs.readFile('schema/raw/query.json', 'utf8'));
  const results = JsonSchema.validate(msg, schema);
  if (!results.valid) {
    console.error('Your query message failed validation:');
    console.error(YAML.stringify(
      results.errors.map(err => omit(err, 'schema')),
      { indent: 2 }
    ));
    process.exit(1);
  }
}

export async function getLastContractAddr(network: Network): Promise<string> {
  try {
    const doc = YAML.parse(await fs.readFile('addrs.yml', 'utf8'));
    const addrs = doc?.[getNetwork(network)];
    if (!addrs?.length)
      error(`No contract addresses found for ${network}`);
    return addrs[addrs.length - 1]?.address
  } catch (err: any) {
    error(`Error reading addrs.yml: ${err.name}: ${err.message}`);
  }
}
