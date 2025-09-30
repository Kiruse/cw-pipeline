import { Signer, type CosmosNetworkConfig } from '@apophis-sdk/core';
import { bech32 } from '@scure/base';
import { inquire } from './prompting';
import { input } from '@inquirer/prompts';
import { fromUtf8, toBase64 } from '@apophis-sdk/core/utils.js';
import { marshal, type MsgsDoc } from './project';

export type Substitutions = Record<string, any>;

export interface MsgContext {
  network: CosmosNetworkConfig;
  signer: Signer;
  subs: Substitutions;
  doc: MsgsDoc[string];
  msgType: 'instantiate' | 'migrate' | `execute:${string}` | `query:${string}`;
}

interface SubContext extends MsgContext {
  name: string;
  type: string;
}

const functions = {
  bin: (ctx: SubContext, args: string[]) => {
    if (args.length !== 1) throw `Invalid arguments for $bin: ${args.join(', ')}. Expected 1 argument.`;

    const [arg] = args;
    if (typeof arg !== 'string') throw `Unsupported argument for $bin: ${arg}`;
    return Promise.resolve(toBase64(fromUtf8(arg)));
  },
  json: (ctx: SubContext, args: string[]) => {
    if (args.length !== 1) throw `Invalid arguments for $json: ${args.join(', ')}. Expected 1 argument.`;
    return Promise.resolve(JSON.stringify(marshal(args[0])));
  },
  signer: (ctx: SubContext, args: string[]) => {
    if (args.length !== 0) throw `Invalid arguments for $signer: ${args.join(', ')}. Expected 0 arguments.`;
    return Promise.resolve(ctx.signer.address(ctx.network));
  },
  tpl: (ctx: SubContext, args: string[]) => {
    if (args.length !== 1) throw `Invalid arguments for $tpl: ${args.join(', ')}. Expected 1 argument.`;
    const [name] = args;
    if (typeof name !== 'string') throw `Unsupported argument for $tpl: ${name}`;

    let tpl: any;
    if (ctx.msgType === 'instantiate' || ctx.msgType === 'migrate') {
      tpl = ctx.doc[ctx.msgType]?.tpls?.[name];
    } else {
      const [msgType, msgName] = ctx.msgType.split(':');
      const msg = ctx.doc[msgType as 'execute' | 'query']?.find(m => m.name === msgName);
      tpl = msg?.tpls?.[name];
    }

    if (!tpl) tpl = ctx.doc.tpls?.[name];
    if (!tpl) throw `Template ${name} not found`;

    return Promise.resolve(processMsg(ctx, tpl));
  },
} satisfies Record<string, PlaceholderFn>;

const types = {
  addr: {
    prompt: (context: SubContext) => {
      return input({
        message: `Enter an address for ${context.name}`,
        validate: (value: string) => {
          try {
            types.addr.parse(context, value);
            return true;
          } catch {
            return false;
          }
        },
      });
    },
    parse: (context: SubContext, value: string): Promise<string> => {
      try {
        bech32.decode(value as any);
        return Promise.resolve(value);
      } catch {
        throw `Invalid address: ${value}`;
      }
    },
  },
} satisfies Record<string, TypeDef>;

type PlaceholderFn = (context: SubContext, args: string[]) => Promise<any>;

interface TypeDef {
  prompt: (context: SubContext) => Promise<string>;
  parse: (context: SubContext, value: string) => Promise<any>;
}

export async function processMsg(ctx: MsgContext, msg: any) {
  if (typeof msg === 'object') {
    for (const key in msg) {
      msg[key] = await processMsg(ctx, msg[key]);
    }
    return msg;
  } else if (typeof msg === 'string' && msg.trim().startsWith('$')) {
    return await substitute(ctx, msg);
  }
}

export async function substitute(msgCtx: MsgContext, msg: string) {
  msg = msg.trim();
  if (!msg.startsWith('$')) throw new Error(`Invalid placeholder: ${msg}`);

  let matches = msg.match(/^\$\((\w+)(?::(\w+))?\)$/);
  if (matches) {
    let [, placeholder, type] = matches;

    if (type) {
      const typ = type as keyof typeof types;
      const ctx: SubContext = { ...msgCtx, name: placeholder, type };
      if (!types[typ]) throw `Invalid placeholder type: ${type}`;
      if (msgCtx.subs[placeholder]) return await types[typ].parse(ctx, msgCtx.subs[placeholder]);
      return await types[typ].parse(ctx, await types[typ].prompt(ctx));
    } else {
      return await inquire(input, {
        name: `placeholder-${placeholder}`,
        message: `Enter a string for ${placeholder}`,
      });
    }
  }

  matches = msg.match(/^\$(\w+)\((.*)\)$/);
  if (!matches) throw `Invalid placeholder: ${msg}`;
  let [, fn, args] = matches;
  throw new Error('not yet implemented');
}
