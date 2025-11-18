import { toHex, toBase64 } from '@apophis-sdk/core/utils.js'
import { LocalSigner } from '@apophis-sdk/cosmos/local-signer.js'
import { Argument, Option } from 'commander'
import fs from 'fs/promises'
import { Project } from '~/project'
import { copy, getWorkspaceDeps, isDir, substitutePlaceholders } from '~/templating'
import { ASSETSDIR, error } from '~/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  cmd = prog.command 'create'
    .description 'Create a new thing.'
  cmd.command 'project'
    .description 'Create a new project.'
    .argument '<name>', 'Name of the project.'
    .action (name, options) ->
      error 'Not yet implemented. This command will deprecate the `init` command, eventually.'
  cmd.command 'contract'
    .description 'Create a new contract in a monorepo.'
    .argument '<name>', 'Name of the contract.'
    .action (name, options) ->
      proj = await Project.find().catch(=>)
      error 'Not in a monorepo.' unless proj?.isMonorepo
      error 'Contract already exists.' if await isDir "#{proj.root}/contracts/#{name}"

      cargo = await fs.readFile "#{proj.root}/Cargo.toml", 'utf8'
      deps = getWorkspaceDeps cargo

      await copy "#{ASSETSDIR}/tpl/contract", "#{proj.root}/contracts/#{name}"
      await substitutePlaceholders "#{proj.root}/contracts/#{name}", { 'project-deps': deps }
      await substitutePlaceholders "#{proj.root}/contracts/#{name}",
        'contract-name': name
        'package-info': [
          'version.workspace = true'
          'authors.workspace = true'
          'edition.workspace = true'
        ].join '\n'
      console.log 'Done.'
      process.exit 0
  cmd.command 'package'
    .description 'Create a new package in a monorepo.'
    .argument '<name>', 'Name of the package.'
    .action (name, options) ->
      proj = await Project.find()
      error 'Not in a monorepo.' unless proj?.isMonorepo
      error 'Package already exists.' if await isDir "#{proj.root}/packages/#{name}"

      cargo = await fs.readFile "#{proj.root}/Cargo.toml", 'utf8'
      deps = getWorkspaceDeps cargo

      await copy "#{ASSETSDIR}/tpl/monorepo/packages/api", "#{proj.root}/packages/#{name}"
      await substitutePlaceholders "#{proj.root}/packages/#{name}", { 'project-deps': deps }
      await substitutePlaceholders "#{proj.root}/packages/#{name}",
        'package-name': name
        'package-info': [
          'version.workspace = true'
          'authors.workspace = true'
          'edition.workspace = true'
        ].join '\n'
      console.log 'Done.'
      process.exit 0
  cmd.command 'mnemonic'
    .description 'Generate a new mnemonic.'
    .addArgument WordsArgument
    .action (nWords, options) ->
      strength = switch nWords
        when 12 then 128
        when 18 then 192
        when 24 then 256
      mnemonic = await LocalSigner.generateMnemonic undefined, strength
      console.log mnemonic
      process.exit 0
  cmd.command 'privkey'
    .description 'Generate a new private key.'
    .addOption PrivKeyEncodingOption
    .action (options) ->
      privkey = await LocalSigner.generatePrivateKey()
      console.log switch options.encoding
        when 'hex' then toHex(privkey)
        when 'base64' then toBase64(privkey)
      process.exit 0

WordsArgument = new Argument '[nWords]', 'Number of words in the mnemonic'
  .choices [12, 18, 24]
  .default 12
PrivKeyEncodingOption = new Option('--encoding <encoding>', 'Encoding of the private key')
  .choices ['hex', 'base64']
  .default 'hex'

getAuthor = (cargo) ->
  lines = cargo.split '\n'
  line = lines.find (line) -> line.startsWith 'authors = '
  error 'Author not found in Cargo.toml.' unless line
  value = line.slice(line.indexOf('=') + 1).trim()
  authors = JSON.parse value
  authors[0]
