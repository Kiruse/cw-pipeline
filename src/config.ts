import fs from 'fs/promises';
import { homedir } from 'os';
import path from 'path';
import YAML from 'yaml';
import { Project } from './project';

export async function loadConfig(proj?: Project): Promise<any> {
  proj ??= await Project.find().catch(() => undefined);

  const tryReadFile = async (filepath: string) => {
    try {
      if (!(await fs.stat(filepath)).isFile())
        return {};
      return await fs.readFile(filepath, 'utf8').then(YAML.parse);
    } catch (e) {
      return {};
    }
  };

  const cfgs = await Promise.all([
    tryReadFile(path.join(homedir(), '.cw-pipeline', 'config.yml')).catch(() => ({})),
    proj ? tryReadFile(path.join(proj.root, 'cwp.yml')).catch(() => ({})) : {},
    proj && proj.project ? tryReadFile(path.join(proj.projectPath, 'cwp.yml')).catch(() => ({})) : {},
  ]);
  return Object.assign({}, ...cfgs);
}
