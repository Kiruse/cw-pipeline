import { type CosmosNetworkConfig } from '@apophis-sdk/core';
import fs from 'fs/promises';
import path from 'path';
import YAML from 'yaml';
import * as z from 'valibot';
import { validateJson } from './prompting';
import { isDir, isFile } from './templating';

const DeploymentConfigSchema = z.object({
  contract: z.string(),
  instantiate: z.optional(z.any()),
  migrate: z.optional(z.any()),
  execute: z.optional(z.array(z.object({
    name: z.string(),
    msg: z.any(),
    funds: z.optional(z.union([
      z.array(z.string()),
      z.literal('prompt'),
    ])),
    /** Templates for use in the messages. These are typically used with `$bin()` or `$json()`
     * to populate nested objects that will be encoded & embedded within the message.
     */
    tpl: z.optional(z.record(z.string(), z.any())),
  }))),
  query: z.optional(z.array(z.object({
    name: z.string(),
    msg: z.any(),
    tpl: z.optional(z.record(z.string(), z.any())),
  }))),
});

const DeploymentDocumentSchema = z.array(DeploymentConfigSchema)
type DeploymentDocument = z.InferOutput<typeof DeploymentDocumentSchema>;

/** Abstraction for a Rust project in the context of a terminal user. */
export class Project {
  #deploymentConfig: DeploymentConfig | undefined;

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

  async getLastContractAddr(network: CosmosNetworkConfig) {
    const doc = YAML.parse(await fs.readFile(path.join(this.projectPath, 'addrs.yml'), 'utf8'));
    const addrs = doc?.[network.name];
    if (!addrs?.length)
      throw new Error(`No contract addresses found for ${network.name}`);
    return addrs[addrs.length - 1]?.address;
  }

  async getLastCodeId(network: CosmosNetworkConfig) {
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

  async addCodeId(network: CosmosNetworkConfig, codeId: bigint) {
    // pseudo-touch
    await fs.appendFile(`${this.projectPath}/codeIds.yml`, '');

    const doc = YAML.parse(await fs.readFile(`${this.projectPath}/codeIds.yml`, 'utf8')) ?? {};
    doc[network.name] = doc[network.name] ?? [];
    doc[network.name].push(codeId);
    await fs.writeFile(`${this.projectPath}/codeIds.yml`, YAML.stringify(doc, { indent: 2 }));
  }

  async addContractAddr(network: CosmosNetworkConfig, codeId: bigint, address: string) {
    // pseudo-touch
    await fs.appendFile(`${this.projectPath}/addrs.yml`, '');

    const doc = YAML.parse(await fs.readFile(`${this.projectPath}/addrs.yml`, 'utf8')) ?? {};
    doc[network.name] = doc[network.name] ?? [];
    doc[network.name].push({ address, codeId });
    await fs.writeFile(`${this.projectPath}/addrs.yml`, YAML.stringify(doc, { indent: 2 }));
  }

  async getDeploymentConfig() {
    if (!this.#deploymentConfig)
      this.#deploymentConfig = await DeploymentConfig.load(`${this.projectPath}/.cwp/deployments`);
    return this.#deploymentConfig;
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

export class DeploymentConfig {
  constructor(public readonly doc: DeploymentDocument) {}

  static async load(filepath: string) {
    return new DeploymentConfig(z.parse(DeploymentDocumentSchema, await loadYamlFile(filepath)));
  }

  get contracts() {
    return Array.from(new Set(this.variants.map(v => v.indexOf('#') >= 0 ? v.split('#')[0] : v)));
  }

  get variants() {
    return this.doc.map(c => c.contract);
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

async function loadYamlFile(filepath: string) {
  const exts = ['yml', 'yaml'];
  if (exts.some(ext => filepath.endsWith(ext))) {
    const idx = filepath.lastIndexOf('.');
    filepath = filepath.slice(0, idx);
  }
  const files = await Promise.all(
    exts.map(ext => fs.readFile(`${filepath}.${ext}`, 'utf8').catch(() => undefined))
  );
  const file = files.find(file => file !== undefined);
  if (!file) throw new Error(`No ${exts.map(ext => `.${ext}`).join(' or ')} file found at ${filepath}`);
  return YAML.parse(file) as unknown;
}
