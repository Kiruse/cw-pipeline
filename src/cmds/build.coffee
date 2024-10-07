import { recase } from '@kristiandupont/recase'
import { $ } from 'bun'
import { basename } from 'path'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  cmd = prog.command 'build'
    .description 'Build your project, for development or production.'
    .argument '[env]', 'Environment to build for. Either "dev" or "prod".', 'dev'
    .option '--optimizer-version', 'Version of the cosmwasm/optimizer to use.', '0.15.0'
    .action (env, options) ->
      releaseFlag = if env == 'dev' then '' else '--release'
      await $"cargo build --lib --target wasm32-unknown-unknown #{releaseFlag}"
      if releaseFlag
        pwd = process.cwd().replaceAll(/\s+/g, '\\ ')
        projCacheName = recase('mixed', 'snake')(basename pwd).replaceAll(/\s+/g, '_')

        vCode = "-v#{pwd}:/code"
        vTargetCache = "-v#{projCacheName}_cache:/target"
        vRegCache = "-vregistry_cache:/usr/local/cargo/registry"
        await $"docker run --rm #{vCode} #{vTargetCache} #{vRegCache} cosmwasm/optimizer:#{options.optimizerVersion}"
