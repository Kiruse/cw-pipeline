import fs from 'fs/promises';
import { homedir } from 'os';
import path from 'path';
import YAML from 'yaml';
import { findProjectRoot } from './utils';

export async function loadConfig(): Promise<any> {
  const tryReadFile = async (filepath: string) => {
    try {
      if (!(await fs.stat(filepath)).isFile())
        return {};
      return await fs.readFile(filepath, 'utf8').then(YAML.parse);
    } catch (e) {
      return {};
    }
  };

  await tryReadFile(path.join(homedir(), '.cw-pipeline', 'config.yml'));

  const [cfg1, cfg2] = await Promise.all([
    tryReadFile(path.join(homedir(), '.cw-pipeline', 'config.yml')),
    tryReadFile(path.join(await findProjectRoot(), 'cwp.yml')),
  ]);
  return Object.assign({}, cfg1, cfg2);
}
