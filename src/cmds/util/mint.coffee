import { error } from 'src/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  cmd = prog.command 'mint'
  mintCw20 cmd
  mintCw721 cmd
  mintNative cmd
  cmd

###* @param {import('commander').Command} prog ###
mintCw20 = (prog) ->
  prog.command 'cw20'
    .action -> error 'not yet implemented'

###* @param {import('commander').Command} prog ###
mintCw721 = (prog) ->
  prog.command 'cw721'
    .action -> error 'not yet implemented'

###* @param {import('commander').Command} prog ###
mintNative = (prog) ->
  prog.command 'native'
    .action -> error 'not yet implemented'
