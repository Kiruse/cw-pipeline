import { snakeCase } from 'case-anything'
import { basename } from 'path'
import { Project } from '~/project'
import { copy, substitutePlaceholders, tryStat, getCrateName } from '~/templating'
import { ASSETSDIR, $exec as $$ } from '~/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  cmd = prog.command 'build'
    .description 'Build your project, for development or production.'
    .argument '[env]', 'Environment to build for. Either "dev" or "prod".', 'dev'
    .option '--optimizer-version', 'Version of the cosmwasm/optimizer to use.', '0.15.0'
    .option '--no-schema', 'Skip building the schema. Incompatible with --schema-only.'
    .option '--schema-only', 'Only build the schema. Incompatible with --no-schema.', false
    .action (env, options) ->
      buildSchema = options.schema ? options.schemaOnly
      proj = await Project.find()

      # TODO: build with chain-specific features using `--features` argument - see https://doc.rust-lang.org/cargo/reference/features.html#command-line-feature-options
      unless options.schemaOnly
        if env is 'dev' or !(await tryStat("#{proj.root}/Cargo.lock"))
          await $$"cargo build --lib --release --target wasm32-unknown-unknown"

        if env is 'prod'
          projCacheName = snakeCase(basename proj.root).replaceAll(/\s+/g, '_')
          vCode = "-v#{proj.root}:/code"
          vTargetCache = "-v#{projCacheName}_cache:/target"
          vRegCache = "-vregistry_cache:/usr/local/cargo/registry"
          await $$"docker run --rm #{vCode} #{vTargetCache} #{vRegCache} cosmwasm/optimizer:#{options.optimizerVersion}"

      if buildSchema
        contracts = if proj.isMonorepo
          await proj.getContractNames().then (contracts) -> contracts.map (c) -> "#{proj.root}/contracts/#{c}"
        else
          [proj.root]

        for contract in contracts
          if !(await tryStat("#{contract}/src/bin/schema.rs"))
            await copy "#{ASSETSDIR}/tpl/scripts/schema.rs", "#{contract}/src/bin/schema.rs"
            await substitutePlaceholders "#{contract}/src/bin/schema.rs",
              'project-crate': await getCrateName contract
          await $$"cd #{contract} && cargo run --bin schema"
