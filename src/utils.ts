import { type CosmosNetworkConfig } from '@apophis-sdk/core';
import { Cosmos } from '@apophis-sdk/cosmos';
import { IBCTypes } from '@apophis-sdk/cosmos/types.sdk.js';
import fs from 'fs/promises'
import os from 'os'
import path from 'path';
import YAML from 'yaml';

/** Chain metadata as returned by `https://chains.cosmos.directory/` */
export interface DirectoryChain {
  name: string;
  path: string;
  chain_name: string;
  network_type: 'mainnet' | 'testnet';
  pretty_name: string;
  chain_id: string;
  status: string;
  bech32_prefix: string;
  slip44: number;
  symbol: string;
  display: string;
  denom: string;
  decimals: number;
  coingecko_id: string;
  image: string;
  height: number | bigint;
  assets: DirectoryAsset[];
}

export interface DirectoryAsset {
  name: string;
  description: string;
  symbol: string;
  denom: string;
  decimals: number;
  coingecko_id: string;
  base: DirectoryAssetUnit;
  display: DirectoryAssetUnit;
  denom_units: DirectoryAssetUnit[];
  /** Map of image mime types to image URLs */
  logo_URIs: Record<string, string>;
  image: string;
}

export interface DirectoryAssetUnit {
  denom: string;
  exponent: number;
}

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

export const ASSETSDIR = path.resolve(__dirname, '../assets');
export const DATADIR   = path.resolve(os.homedir(), '.cw-pipeline');

export function error(...msgs: any[]): never {
  console.error(...msgs.map(msg => msg instanceof Error ? `${msg.name}: ${msg.message}\n${msg.stack}` : msg));
  process.exit(1);
}

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

export async function log(network: CosmosNetworkConfig, data: unknown) {
  await fs.appendFile(
    'cw-pipeline.log',
    `[${getLogTimestamp()} ${network.chainId}]\n` +
    YAML.stringify(data, { indent: 2 }) + '\n\n',
  );
}

export function omit<T, K extends keyof T>(obj: T, ...keys: K[]): Omit<T, K> {
  const result = { ...obj };
  for (const key of keys)
    delete result[key];
  return result;
}

export async function spawn(cmd: string, args: string[], opts: { cwd?: string } = {}) {
  const { spawn } = await import('child_process');
  return new Promise<void>((resolve, reject) => {
    const proc = spawn(cmd, args, { stdio: 'inherit', ...opts });
    proc.on('error', reject);
    proc.on('exit', (code) => {
      if (code === 0) resolve()
      else reject(code);
    });
  });
}

export async function exec(cmd: string, args: string[], opts: { cwd?: string } = {}) {
  const { exec } = await import('child_process');
  return new Promise<{ stdout: string; stderr: string }>((resolve, reject) => {
    exec(`${cmd} ${args.join(' ')}`, opts, (err, stdout, stderr) => {
      if (err) reject(err);
      else resolve({stdout, stderr});
    });
  });
}

// Custom template literal for executing shell commands using child_process
export function $exec(strings: TemplateStringsArray, ...values: any[]): Promise<void> {
  const { exec } = require('child_process');

  // Build the command string by interpolating values
  let command = '';
  for (let i = 0; i < strings.length; i++) {
    command += strings[i];
    if (i < values.length) {
      command += String(values[i]);
    }
  }

  return new Promise<void>((resolve, reject) => {
    exec(command, { stdio: 'inherit' }, (error: any) => {
      if (error) {
        reject(error);
      } else {
        resolve();
      }
    });
  });
}

/** Get the list of chains from `https://chains.cosmos.directory/` */
export async function getChainDirectory(): Promise<DirectoryChain[]> {
  const res = await fetch('https://chains.cosmos.directory/');
  const data: any = await res.json();
  return data.chains;
}

/** Attempt to find a chain by its ID. Prioritizes exact matches, then tries to strip the chain ID
 * sequence (assuming the format `prefix-<sequence_number>`) to find a chain with the same prefix.
 */
export async function findChainById(chainId: string, chains?: DirectoryChain[]): Promise<DirectoryChain | undefined> {
  chains ??= await getChainDirectory();
  const chainIdParts = chainId.split('-');
  if (chainIdParts[chainIdParts.length - 1].match(/^\d+$/)) {
    chainIdParts.pop();
  }
  const chainIdPrefix = chainIdParts.join('-');
  return chains.find((c) => c.chain_id === chainId) ??
    chains.find((c) => c.chain_id.startsWith(chainIdPrefix));
}

// Cache for IBC collection functions (keyed by chainId)
const denomTracesCache = new Map<string, IBCTypes.DenomTrace[]>();
const channelsCache = new Map<string, IBCTypes.Channel[]>();
const connectionsCache = new Map<string, IBCTypes.Connection[]>();
const clientsCache = new Map<string, IBCTypes.ClientState[]>();

export async function collectDenomTraces(network: CosmosNetworkConfig) {
  const cacheKey = network.chainId;
  if (denomTracesCache.has(cacheKey)) {
    return denomTracesCache.get(cacheKey)!;
  }

  let response = await Cosmos.rest(network).ibc.apps.transfer.v1.denom_traces('GET');
  const allDenomTraces = response.denom_traces;
  while (response.pagination.next_key) {
    response = await Cosmos.rest(network).ibc.apps.transfer.v1.denom_traces('GET', {
      query: {
        'pagination.key': response.pagination.next_key
      },
    } as any);
    allDenomTraces.push(...response.denom_traces);
  }
  denomTracesCache.set(cacheKey, allDenomTraces);
  return allDenomTraces;
}

export async function collectChannels(network: CosmosNetworkConfig) {
  const cacheKey = network.chainId;
  if (channelsCache.has(cacheKey)) {
    return channelsCache.get(cacheKey)!;
  }

  let response = await Cosmos.rest(network).ibc.core.channel.v1.channels('GET');
  const allChannels = response.channels;
  while (response.pagination.next_key) {
    response = await Cosmos.rest(network).ibc.core.channel.v1.channels('GET', {
      query: {
        'pagination.key': response.pagination.next_key
      },
    } as any);
    allChannels.push(...response.channels);
  }
  channelsCache.set(cacheKey, allChannels);
  return allChannels;
}

export async function collectConnections(network: CosmosNetworkConfig) {
  const cacheKey = network.chainId;
  if (connectionsCache.has(cacheKey)) {
    return connectionsCache.get(cacheKey)!;
  }

  let response = await Cosmos.rest(network).ibc.core.connection.v1.connections('GET');
  const allConnections = response.connections;
  while (response.pagination.next_key) {
    response = await Cosmos.rest(network).ibc.core.connection.v1.connections('GET', {
      query: {
        'pagination.key': response.pagination.next_key
      },
    } as any);
    allConnections.push(...response.connections);
  }
  connectionsCache.set(cacheKey, allConnections);
  return allConnections;
}

export async function collectClients(network: CosmosNetworkConfig) {
  const cacheKey = network.chainId;
  if (clientsCache.has(cacheKey)) {
    return clientsCache.get(cacheKey)!;
  }

  let response = await Cosmos.rest(network).ibc.core.client.v1.client_states('GET');
  const allClients = response.client_states;
  while (response.pagination.next_key) {
    response = await Cosmos.rest(network).ibc.core.client.v1.client_states('GET', {
      query: {
        'pagination.key': response.pagination.next_key
      },
    } as any);
    allClients.push(...response.client_states);
  }
  clientsCache.set(cacheKey, allClients);
  return allClients;
}

export async function findChannel(network: CosmosNetworkConfig, channelId: string) {
  try {
    const response = await Cosmos.rest(network).ibc.core.channel.v1.channels[channelId]('GET');
    return response.channel;
  } catch {
    const channels = await collectChannels(network);
    return channels.find((c) => c.channel_id === channelId);
  }
}

export async function findConnection(network: CosmosNetworkConfig, connectionId: string) {
  try {
    const response = await Cosmos.rest(network).ibc.core.connection.v1.connections[connectionId]('GET');
    return response.connection;
  } catch {
    const connections = await collectConnections(network);
    return connections.find((c) => c.id === connectionId);
  }
}

export async function findClient(network: CosmosNetworkConfig, clientId: string) {
  try {
    const response = await Cosmos.rest(network).ibc.core.client.v1.client_states[clientId]('GET');
    return response.client_state;
  } catch {
    const clients = await collectClients(network);
    return clients.find((c) => c.client_id === clientId);
  }
}
