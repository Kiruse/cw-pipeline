import { LCDClient, MnemonicKey, MnemonicKeyOptions } from '@terra-money/feather.js/src';
import fs from 'fs/promises'
import os from 'os'

export type Network = 'mainnet' | 'testnet';

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
