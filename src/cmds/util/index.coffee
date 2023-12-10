import MintCommand from './mint.coffee'

subcommands = [
  MintCommand
]

###* @param {import('commander').Command} prog ###
export default (prog) ->
  cmd = prog.command 'util'
    .description 'General purpose commands for common use cases.'
  sub cmd for sub in subcommands
  cmd
