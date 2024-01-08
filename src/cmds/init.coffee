import { file } from 'bun'
import inquirer from 'inquirer'
import fs from 'fs/promises'
import os from 'os'
import path from 'path'
import { error, spawn, TMPDIR, getLastInquire, saveLastInquire, ASSETSDIR } from 'src/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'init'
    .description 'Initialize a new CosmWasm project. Assumes tools were already installed with `cw-pipeline setup`.'
    .action ->
      #region inquire
      {monorepo, answers...} = await inquirer.prompt [
        type: 'input'
        name: 'name'
        message: 'What is the name of your project?'
        default: -> process.cwd().replace(/\\/g, /\//).split('/').pop()
      ,
        type: 'input'
        name: 'path'
        message: 'Where would you like to setup your new project?'
        default: (answers) -> "./#{answers.name}"
      ,
        type: 'input'
        name: 'author'
        message: 'Who is the author of this project?'
        default: await getLastInquire 'author', os.userInfo().username
      ,
        type: 'confirm'
        name: 'monorepo'
        message: 'Would you like to setup a monorepo?'
        default: -> false
      ,
        type: 'confirm'
        name: 'cw-1.4'
        message: 'Does your target chain support CosmWasm 1.4?'
        default: -> false
      ]
      #endregion inquire
      await saveLastInquire answers
      if monorepo then error 'Monorepo support is not yet implemented.'

      #region copy
      target = path.resolve answers.path
      tplFiles = await getTemplateFiles()
      copyFiles = tplFiles.filter (file) -> not file.match /^_.*?\//
      contractFiles = tplFiles.filter (file) -> file.startsWith '_contract/'
        .map (file) -> file.replace /^_contract\//, ''

      await mkdirs Array.from(new Set copyFiles.map (file) -> "#{target}/#{path.dirname file}")
      await Promise.all copyFiles.map (file) ->
        await fs.copyFile "#{ASSETSDIR}/tpl/#{file}", "#{target}/#{file}"

      copyContractFiles = (dir) ->
        await mkdirs Array.from(new Set contractFiles.map (file) -> "#{dir}/#{path.dirname file}")
        await Promise.all contractFiles.map (file) ->
          await fs.copyFile "#{ASSETSDIR}/tpl/_contract/#{file}", "#{dir}/#{file}"
      await copyContractFiles if monorepo then "#{target}/contracts/#{answers.name}" else "#{target}/src"
      #endregion copy

      #region replace Cargo.toml placeholders
      cargoToml = await fs.readFile "#{target}/Cargo.toml", 'utf8'
      cargoToml = cargoToml.replace /\{\{project-name\}\}/g, answers.name
      cargoToml = cargoToml.replace /\{\{authors\}\}/g, answers.author
      if answers['cw-1.4']
        cargoToml = cargoToml.replace 'features = ["cosmwasm_1_3"]', 'features = ["cosmwasm_1_4"]'
      # TODO: monorepos aka workspaces
      await fs.writeFile "#{target}/Cargo.toml", cargoToml
      #endregion replace Cargo.toml placeholders

      #region replace Readme placeholders
      readme = await fs.readFile "#{target}/README.md", 'utf8'
      readme = readme.replace /\{\{project-name\}\}/g, answers.name
      await fs.writeFile "#{target}/README.md", readme
      #endregion replace Readme placeholders

      try
        await spawn 'git', ['init'], cwd: target
        await spawn 'git', ['add', '.'], cwd: target
        await spawn 'git', ['commit', '-m', 'Initial commit'], cwd: target
      catch
        console.error "Failed to fully initialize git repository in #{target}."
      console.log 'Done.'

mkdirs = (dirs) -> await Promise.all dirs.map (dir) -> await fs.mkdir dir, recursive: true
getTemplateFiles = ->
  files = []
  recurse = (dir) ->
    entries = await fs.readdir dir, withFileTypes: true
    for entry in entries
      if entry.isDirectory()
        await recurse "#{dir}/#{entry.name}"
      else
        files.push "#{dir}/#{entry.name}"
  await recurse ASSETSDIR
  files.map (file) -> file.replace "#{ASSETSDIR}/tpl/", ''
