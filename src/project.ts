import fs from 'fs/promises';
import path from 'path';
import YAML from 'yaml';
import { validateJson } from './prompting';
import { NetworkConfig } from '@apophis-sdk/core';
import { isDir, isFile } from './templating';

/** Abstraction for a Rust project in the context of a terminal user. */
export class Project {
  constructor(
    /** The root project directory. If we're inside a monorepo, this is the monorepo root. */
    public root: string,
    /** The current project name. Only provided if we're inside a monorepo. */
    public project: string | undefined,
    /** Whether we're inside a monorepo. */
    public isMonorepo: boolean,
    /** Whether we're currently inside a valid smart contract project. */
    public isContractProject: boolean,
  ) {}

  validateMsg(msg: any, kind: 'instantiate' | 'execute' | 'query') {
    return validateJson(msg, `${this.projectPath}/schema/raw/${kind}.json`);
  }

  async activate(project: string | undefined) {
    if (project === undefined) {
      this.project = undefined;
      return this;
    }

    if (!this.isMonorepo)
      throw new Error(`Cannot activate subproject ${project} in non-monorepo`);
    if (!(await isDir(path.join(this.root, 'contracts', project))))
      throw new Error(`Subproject ${project} not found`);
    this.project = project;
    return this;
  }

  async getLastContractAddr(network: NetworkConfig) {
    const doc = YAML.parse(await fs.readFile(path.join(this.projectPath, 'addrs.yml'), 'utf8'));
    const addrs = doc?.[network.name];
    if (!addrs?.length)
      throw new Error(`No contract addresses found for ${network.name}`);
    return addrs[addrs.length - 1]?.address;
  }

  async getLastCodeId(network: NetworkConfig) {
    if (this.isMonorepo && !this.project)
      throw 'You must select a project when working with monorepos.';

    const filepath = path.join(this.projectPath, 'codeIds.yml');
    if (!(await isFile(filepath)))
      throw `No code IDs found for ${network.name}`;

    const doc = YAML.parse((await fs.readFile(filepath, 'utf8')).trim());
    const codeIds = doc[network.name];
    if (!codeIds?.length)
      throw `No code IDs found for ${network.name}`;
    return BigInt(codeIds[codeIds.length - 1]);
  }

  async getContractNames() {
    if (!this.isMonorepo) throw new Error('Project is not a monorepo');
    return await fs.readdir(path.join(this.root, 'contracts'));
  }

  async addCodeId(network: NetworkConfig, codeId: bigint) {
    // pseudo-touch
    await fs.appendFile(`${this.projectPath}/codeIds.yml`, '');

    const doc = YAML.parse(await fs.readFile(`${this.projectPath}/codeIds.yml`, 'utf8')) ?? {};
    doc[network.name] = doc[network.name] ?? [];
    doc[network.name].push(codeId);
    await fs.writeFile(`${this.projectPath}/codeIds.yml`, YAML.stringify(doc, { indent: 2 }));
  }

  async addContractAddr(network: NetworkConfig, codeId: bigint, address: string) {
    // pseudo-touch
    await fs.appendFile(`${this.projectPath}/addrs.yml`, '');

    const doc = YAML.parse(await fs.readFile(`${this.projectPath}/addrs.yml`, 'utf8')) ?? {};
    doc[network.name] = doc[network.name] ?? [];
    doc[network.name].push({ address, codeId });
    await fs.writeFile(`${this.projectPath}/addrs.yml`, YAML.stringify(doc, { indent: 2 }));
  }

  static async find(root = process.cwd()) {
    const first = await findRustProject(root).catch(() => undefined);
    if (!first) throw new Error('No Rust project found');

    if (await detectMonorepo(first))
      return new Project(first, undefined, true, false);

    const parent = await findRustProject(path.dirname(first)).catch(() => undefined);
    if (parent && await detectMonorepo(parent)) {
      const parts = path.relative(parent, first).split(path.sep);
      if (parts.length !== 2 || parts[0] !== 'contracts')
        throw new Error('Unexpected monorepo structure');
      return new Project(parent, parts[1], true, true);
    }

    return new Project(first, undefined, false, true);
  }

  get projectPath() {
    return this.project ? `${this.root}/contracts/${this.project}` : this.root;
  }
}

async function isRustProject(dir: string) {
  try {
    const stat = await fs.stat(path.join(dir, 'Cargo.toml'));
    return stat.isFile();
  } catch {
    return false;
  }
}

async function findRustProject(dir = process.cwd()): Promise<string> {
  while (dir !== '/') {
    if (await isRustProject(dir))
      return dir;
    dir = path.dirname(dir);
  }
  throw new Error('Could not find project root');
}

async function detectMonorepo(dir: string) {
  const contents = await fs.readFile(`${dir}/Cargo.toml`, 'utf8');
  const lines = contents.split('\n');
  return lines.includes('[workspace]');
}
