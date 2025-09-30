import { type CosmosNetworkConfig } from '@apophis-sdk/core';
import fs from 'fs/promises';
import path from 'path';
import YAML from 'yaml';
import * as z from 'valibot';
import { validateJson } from './prompting';
import { isDir, isFile } from './templating';
import { BigintMarshalUnit, DateMarshalUnit, extendDefaultMarshaller } from '@kiruse/marshal';
import { Coin } from '@apophis-sdk/core/types.sdk.js';

const { marshal, unmarshal } = extendDefaultMarshaller([
  BigintMarshalUnit,
  DateMarshalUnit,
]);

const DeploymentConfigSchema = z.object({
  id: z.optional(z.string()),
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
  dependencies: z.optional(z.array(z.string())),
});

const CodeIdsSchema = z.record(
  z.string(), // network name
  z.record(
    z.string(), // contract name
    z.array(
      z.object({
        codeId: z.union([z.bigint(), z.number()]),
        timestamp: z.optional(z.date()),
      })
    )
  )
);

const AddrsSchema = z.record(
  z.string(), // network name
  z.record(
    z.string(), // contract name
    z.array(z.object({
      name: z.string(),
      address: z.string(),
      codeId: z.union([z.bigint(), z.number()]),
      timestamp: z.optional(z.date()),
    }))
  )
);

const MsgsSchema = z.record(
  z.string(), // contract name
  z.object({
    instantiate: z.optional(z.object({
      msg: z.any(),
      funds: z.optional(z.union([
        z.array(z.string()),
        z.literal('prompt'),
      ])),
    })),
    migrate: z.optional(z.object({
      msg: z.any(),
    })),
    execute: z.optional(z.array(
      z.object({
        name: z.string(),
        msg: z.any(),
        funds: z.optional(z.union([
          z.array(z.string()),
          z.literal('prompt'),
        ])),
      })
    )),
    query: z.optional(z.array(
      z.object({
        name: z.string(),
        msg: z.any(),
      })
    )),
  })
);

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

  async getLastContractAddr(network: CosmosNetworkConfig, contract: string) {
    const doc = await this.loadAddrs();
    const byContract = doc[network.name];
    const candidates = Object.values(byContract).flat().filter(c => c.name === contract);
    if (candidates.length === 0)
      throw `No addresses found for ${contract} on ${network.name}`;
    if (candidates.length > 1)
      throw `Multiple addresses found for ${contract} on ${network.name}`;
    return candidates[0].address;
  }

  async getLastCodeId(network: CosmosNetworkConfig, contract: string) {
    const doc = await this.loadCodeIds();
    const codeIds = doc[network.name]?.[contract];
    if (!codeIds?.length)
      throw `No code IDs found for ${contract} on ${network.name}`;
    return codeIds[codeIds.length - 1].codeId;
  }

  async getCurrentCodeId(network: CosmosNetworkConfig, name: string): Promise<bigint | number | undefined> {
    return (await this.getDeployedContract(network, name))?.codeId;
  }

  async getStoredContracts(network: CosmosNetworkConfig) {
    const doc = await this.loadCodeIds();
    return Object.keys(doc[network.name] ?? {});
  }

  async getDeployedContracts(network: CosmosNetworkConfig) {
    const doc = await this.loadAddrs();
    const byContract = doc[network.name] ?? {};
    return Object.entries(byContract).flatMap(([contract, values]) => values.map(value => ({ ...value, contract })));
  }

  async getDeployedContract(network: CosmosNetworkConfig, name: string) {
    return (await this.getDeployedContracts(network)).find(c => c.name === name);
  }

  async loadCodeIds() {
    const filepath = path.join(this.root, '.cwp', 'codeIds.yml');
    const doc = unmarshal(YAML.parse((await fs.readFile(filepath, 'utf8').catch(() => ''))));
    return z.parse(CodeIdsSchema, doc);
  }

  async loadAddrs() {
    const filepath = path.join(this.root, '.cwp', 'addrs.yml');
    const doc = unmarshal(YAML.parse((await fs.readFile(filepath, 'utf8').catch(() => ''))));
    return z.parse(AddrsSchema, doc);
  }

  /** Load the message for the given contract and type. If no message is found, the `msg` field will
   * be `undefined`.
   */
  async getMsg(
    network: CosmosNetworkConfig,
    contract: string,
    type: 'instantiate' | 'migrate' | `execute.${string}` | `query.${string}`,
    placeholders: Record<string, any> = {},
  ): Promise<{ msg: any, funds: Coin[] }> {
    // TODO: substitute placeholders
    // TODO: funds
    const filepath = path.join(this.root, '.cwp', 'msgs.yml');
    const doc = z.parse(MsgsSchema, unmarshal(YAML.parse((await fs.readFile(filepath, 'utf8').catch(() => '')))));
    if (type === 'instantiate') {
      if (!doc[contract]?.instantiate) return { msg: undefined, funds: [] };
      return {
        ...doc[contract].instantiate,
        funds: [],
      };
    }
    if (type === 'migrate') {
      if (!doc[contract]?.migrate) return { msg: undefined, funds: [] };
      return {
        ...doc[contract].migrate,
        funds: [],
      };
    }
    if (type.startsWith('execute.')) {
      const data = doc[contract]?.execute?.find(e => e.name === type.split('.')[1]);
      if (!data) return { msg: undefined, funds: [] };
      return {
        ...data?.msg,
        funds: [],
      };
    }
    if (type.startsWith('query.')) {
      const data = doc[contract]?.query?.find(q => q.name === type.split('.')[1]);
      if (!data) return { msg: undefined, funds: [] };
      return {
        ...data?.msg,
        funds: [],
      };
    }
    throw new Error(`Invalid message type: ${type}`);
  }

  async validateMsg(contract: string, kind: 'instantiate' | 'migrate' | 'execute' | 'query', msg: any) {
    const variants = [`${contract.replace(/_/g, '-')}`, `${contract.replace(/-/g, '_')}`];
    const filepaths = variants.map(variant => `${this.root}/contracts/${variant}/schema/${variant}.json`);
    for (const filepath of filepaths) {
      if (await isFile(filepath)) {
        const container = JSON.parse(await fs.readFile(filepath, 'utf8'));
        const schema = container[kind];
        if (!schema) throw `Schema ${kind} not supported by ${contract}`;
        await validateJson(marshal(msg), schema);
        return;
      }
    }
    throw new Error(`No schema found for ${contract} in ${filepaths.join(', ')}`);
  }

  async saveAddrs(addrs: z.InferOutput<typeof AddrsSchema>) {
    await fs.writeFile(path.join(this.root, '.cwp', 'addrs.yml'), YAML.stringify(marshal(addrs), { indent: 2 }));
  }

  async saveCodeIds(codeIds: z.InferOutput<typeof CodeIdsSchema>) {
    await fs.writeFile(path.join(this.root, '.cwp', 'codeIds.yml'), YAML.stringify(marshal(codeIds), { indent: 2 }));
  }

  async getContractNames() {
    if (!this.isMonorepo) throw new Error('Project is not a monorepo');
    return await fs.readdir(path.join(this.root, 'contracts'));
  }

  async addCodeId(network: CosmosNetworkConfig, contract: string, codeId: bigint) {
    await fs.mkdir(`${this.root}/.cwp`, { recursive: true });
    const contents = await fs.readFile(`${this.root}/.cwp/codeIds.yml`, 'utf8').catch(() => '');
    const doc = YAML.parse(contents) ?? {};
    doc[network.name] = doc[network.name] ?? {};
    doc[network.name][contract] ??= [];
    doc[network.name][contract].push({ codeId, timestamp: new Date().toISOString() });
    await fs.writeFile(`${this.root}/.cwp/codeIds.yml`, YAML.stringify(doc, { indent: 2 }));
  }

  async addContractAddr(network: CosmosNetworkConfig, contract: string, name: string, codeId: bigint, address: string) {
    await fs.mkdir(`${this.root}/.cwp`, { recursive: true });
    const contents = await fs.readFile(`${this.root}/.cwp/addrs.yml`, 'utf8').catch(() => '');
    const doc = YAML.parse(contents) ?? {};
    doc[network.name] ??= {};
    doc[network.name][contract] ??= [];
    doc[network.name][contract].push({ name, address, codeId, timestamp: new Date() });
    await fs.writeFile(`${this.root}/.cwp/addrs.yml`, YAML.stringify(doc, { indent: 2 }));
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
