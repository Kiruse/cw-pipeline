import { LCDClient, MnemonicKey, MnemonicKeyOptions } from '@terra-money/feather.js/src';
import { Option } from 'commander';
import fs from 'fs/promises'
import os from 'os'

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

async function getMnemonic(): Promise<string> {
  let mnemonic: string | undefined;
  try {
    mnemonic = await fs.readFile(`${os.homedir()}/.shh/mnemonic`, 'utf8');
  } catch {}
  if (!mnemonic)
    try {
      mnemonic = await fs.readFile('./.shh/mnemonic', 'utf8');
    } catch {}
  if (!mnemonic)
    mnemonic = process.env.MNEMONIC
  if (!mnemonic)
    throw Error('No mnemonic found')
  return mnemonic.trim();
}

export const getMnemonicKey = async (opts: Omit<MnemonicKeyOptions, 'mnemonic'> = {}) => new MnemonicKey({ mnemonic: await getMnemonic(), ...opts });

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

export const NetworkOption = (flags = '-n, --network') =>
  new Option(
    `${flags} <network>`,
    'Network to operate on.',
  ).choices(['mainnet', 'testnet']);
