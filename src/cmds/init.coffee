import { confirm, input, select } from '@inquirer/prompts'
import { $ as $$ } from 'bun'
import fs from 'fs/promises'
import os from 'os'
import path from 'path'
import { inquire } from '~/prompting'
import { copy, move, substitutePlaceholders, getSection, getWorkspaceDeps } from '~/templating'
import { ASSETSDIR } from '~/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'init'
    .description 'Initialize a new CosmWasm project. Assumes tools were already installed with `cw-pipeline setup`.'
    .argument '[name]', 'Name of the project'
    .option '--target <target>', 'Target directory'
    .action (name, opts) ->
      #region inquire
      name = await inquire input,
        name: 'name'
        volatile: true
        message: 'What is the name of your project?'
        default: -> process.cwd().replace(/\\/g, /\//).split('/').pop()
        options: { opts..., name }
      target = await inquire input,
        name: 'target'
        volatile: true
        message: 'Where would you like to setup your new project?'
        default: "./#{name}"
        options: opts
      author = await inquire input,
        name: 'author'
        message: 'Who is the author of this project?'
        default: -> os.userInfo().username
        options: opts
      monorepo = await inquire confirm,
        name: 'monorepo'
        message: 'Would you like to setup a monorepo?'
        default: -> false
        options: opts
      cwFeat = await inquire select,
        name: 'cw-version'
        message: 'Which CosmWasm version are you targeting? This depends on your target chain(s).'
        default: '1.4'
        choices: [
          { name: 'CosmWasm 1.3', value: '1.3' }
          { name: 'CosmWasm 1.4', value: '1.4' }
          { name: 'CosmWasm 2.0', value: '2.0' }
          { name: 'CosmWasm 2.1', value: '2.1' }
          { name: 'CosmWasm 2.2', value: '2.2' }
        ]
        options: opts
      #endregion inquire

      target = path.resolve target

      #region update Cargo.toml
      cargo = await fs.readFile "#{ASSETSDIR}/tpl/monorepo/Cargo.toml", 'utf8'
      deps = if monorepo then getWorkspaceDeps(cargo) else getSection(cargo, 'workspace.dependencies')
      if monorepo
        await copy "#{ASSETSDIR}/tpl/monorepo", target
        await copy "#{ASSETSDIR}/tpl/contract", "#{target}/contracts/#{name}"
      else
        await copy "#{ASSETSDIR}/tpl/contract", target
      await copy "#{ASSETSDIR}/tpl/root", target
      #endregion update Cargo.toml

      #region replace placeholders
      await substitutePlaceholders target, {'project-deps': deps} # these contain other placeholders
      await substitutePlaceholders target,
        'project-name': name
        author: author
        'cw-version': (-> cwFeat.match(/^(\d+)\./)?[1] ? '1.5')()
        'cw-features': "cosmwasm_#{cwFeat.replace '.', '_'}"
      unless monorepo
        profiles = getSection cargo, '[profile.release]'
        await fs.appendFile "#{target}/Cargo.toml", "\n[profile.release]\n" + profiles
      #endregion replace placeholders

      try
        await $$"cd #{target} && git init"
        await $$"cd #{target} && git add ."
        await $$"cd #{target} && git commit -m 'Initial commit'"
      catch
        console.error "Failed to fully initialize git repository in #{target}."
      console.log 'Done.'
