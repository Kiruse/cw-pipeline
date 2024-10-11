import { type NetworkConfig } from '@apophis-sdk/core';
import fs from 'fs/promises'
import os from 'os'
import path from 'path';
import YAML from 'yaml';

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

export const ASSETSDIR = path.resolve(import.meta.dir, '../assets');
export const DATADIR   = path.resolve(os.homedir(), '.cw-pipeline');
export const TMPDIR    = path.resolve(import.meta.dir, '../tmp');

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

export async function log(network: NetworkConfig, data: unknown) {
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

export async function getLastContractAddr(network: NetworkConfig): Promise<string> {
  try {
    const doc = YAML.parse(await fs.readFile('addrs.yml', 'utf8'));
    const addrs = doc?.[network.name];
    if (!addrs?.length)
      error(`No contract addresses found for ${network.name}`);
    return addrs[addrs.length - 1]?.address
  } catch (err: any) {
    error(`Error reading addrs.yml: ${err.name}: ${err.message}`);
  }
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

export async function findProjectRoot(): Promise<string> {
  let dir = process.cwd();
  while (dir !== '/') {
    if (await fs.stat(path.join(dir, 'Cargo.toml')).then(stat => stat.isFile()))
      return dir;
    dir = path.dirname(dir);
  }
  error('Could not find project root');
}
