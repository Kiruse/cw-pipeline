import { recase } from '@kristiandupont/recase'
import { $ as $$ } from 'bun'
import { basename } from 'path'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  cmd = prog.command 'build'
    .description 'Build your project, for development or production.'
    .argument '[env]', 'Environment to build for. Either "dev" or "prod".', 'dev'
    .option '--optimizer-version', 'Version of the cosmwasm/optimizer to use.', '0.15.0'
    .option '--schema', 'Build the schema. Schema is always built in production.', false
    .option '--schema-only', 'Only build the schema.', false
    .action (env, options) ->
      releaseFlag = if env is 'dev' then '' else '--release'
      buildSchema = options.schema or options.schemaOnly

      unless options.schemaOnly
        await $$"cargo build --lib --target wasm32-unknown-unknown #{releaseFlag}"

        if releaseFlag
          pwd = process.cwd().replaceAll(/\s+/g, '\\ ')
          projCacheName = recase('mixed', 'snake')(basename pwd).replaceAll(/\s+/g, '_')

          vCode = "-v#{pwd}:/code"
          vTargetCache = "-v#{projCacheName}_cache:/target"
          vRegCache = "-vregistry_cache:/usr/local/cargo/registry"
          await $$"docker run --rm #{vCode} #{vTargetCache} #{vRegCache} cosmwasm/optimizer:#{options.optimizerVersion}"

      if env is 'prod' or buildSchema
        await $$"cargo run --bin schema"
