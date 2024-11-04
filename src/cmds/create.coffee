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


getAuthor = (cargo) ->
  lines = cargo.split '\n'
  line = lines.find (line) -> line.startsWith 'authors = '
  error 'Author not found in Cargo.toml.' unless line
  value = line.slice(line.indexOf('=') + 1).trim()
  authors = JSON.parse value
  authors[0]
