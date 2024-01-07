import * as childProcess from 'child_process'
import * as semver from 'semver'
import { error, exec, spawn } from 'src/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'setup'
    .description 'Setup your CosmWasm Smart Contract development environment.'
    .action ->
      rustupVersion = await getExecVersion 'rustup'
      if rustupVersion is null
        error "rustup is not installed. Please follow the installation instructions from https://rustup.sh/"
      else unless semver.satisfies rustupVersion, '^1.24'
        error "Your current rustup version is #{rustupVersion}, but at least 1.24 is required. Please update (https://rustup.sh/)."

      dockerVersion = await getExecVersion 'docker'
      if dockerVersion is null
        error "docker is not installed. Please follow the installation instructions from https://www.docker.com/"
      else unless semver.satisfies dockerVersion, '>=24'
        error "Your current docker version is #{dockerVersion}, but at least 24 is required. Please update (https://www.docker.com/)."

      {stdout: targets} = (await exec 'rustup', ['target', 'list', '--installed'])
      targets = targets.split '\n'
      unless 'wasm32-unknown-unknown' in targets
        await spawn 'rustup', ['target', 'add', 'wasm32-unknown-unknown']
      console.log 'Your environment should be ready to go! Happy coding! 🚀'

###* Get the parsed version of the given command. Attempts to detect if the command was not found
# in the operation system's path and returns null in that case.
# @param {string} cmd command to check for
# @param {string[]} [args=['--version']] arguments to pass to the command
# @returns {Promise<semver.SemVer | null>}
###
getExecVersion = (cmd, args = ['--version']) -> await new Promise (resolve, reject) ->
  childProcess.exec "#{cmd} #{args.join ' '}", (err, stdout, stderr) ->
    if err
      if err.message.startsWith 'Command failed:'
        resolve null
      else
        reject err
      return
    [line] = stdout.toLowerCase().split '\n'
    parts = line.split ' '
    unless parts.length then reject new CommandParseError cmd, args
    if parts[0] is cmd then parts.shift()
    if parts[0] is 'version' then parts.shift()
    try
      act = semver.coerce parts[0]
      if act
        resolve act
      else
        reject new CommandParseError cmd, args
    catch err
      reject err

class CommandParseError extends Error
  constructor: (cmd, args) ->
    super "Failed to parse version from `#{cmd} #{args.join ' '}` output."
    @name = 'ParseError'
