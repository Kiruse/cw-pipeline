import fs from 'fs/promises';
import { homedir } from 'os';
import path from 'path';
import * as z from 'valibot';
import YAML from 'yaml';
import { Project } from './project';
import { CosmosNetworkConfig } from '@apophis-sdk/core';

const FungibleAssetSchema = z.object({
  denom: z.string(),
  name: z.string(),
  cgid: z.optional(z.string()),
  cmcid: z.optional(z.string()),
  decimals: z.optional(z.number()),
  display: z.optional(z.object({
    denom: z.string(),
    symbol: z.optional(z.string()),
    decimals: z.optional(z.number()),
    aliases: z.optional(z.array(z.string())),
  })),
});

const GasConfigSchema = z.object({
  asset: FungibleAssetSchema,
  minFee: z.optional(z.number()),
  lowPrice: z.optional(z.number()),
  avgPrice: z.number(),
  highPrice: z.optional(z.number()),
  flatGasOffset: z.optional(z.number()),
  gasMultiplier: z.optional(z.number()),
});

const ConfigSchema = z.record(z.string(), z.object({
  network: z.optional(z.object({
    chainId: z.string(),
    name: z.string(),
    prettyName: z.optional(z.string()),
    addressPrefix: z.string(),
    assets: z.optional(z.array(FungibleAssetSchema)),
    gas: z.array(GasConfigSchema),
    gasFactor: z.optional(z.number()),
  })),
  endpoints: z.optional(z.object({
    rest: z.string(),
    rpc: z.string(),
    ws: z.string(),
  })),
}));

export async function loadConfig(proj?: Project) {
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

  const data = z.parse(ConfigSchema, Object.assign({}, ...cfgs));
  return Object.fromEntries(
    Object.entries(data).map(([name, cfg]) => [name, parseNetwork(cfg)])
  );
}

function parseNetwork(data: z.InferOutput<typeof ConfigSchema>[string]) {
  let network: CosmosNetworkConfig | undefined;
  if (data.network) {
    network = {
      ...data.network,
      ecosystem: 'cosmos',
      prettyName: data.network.prettyName ?? data.network.name,
      assets: data.network.assets ?? [],
      gasFactor: data.network.gasFactor ?? 1.2,
    }
  }

  return {
    ...data,
    network,
  };
}
