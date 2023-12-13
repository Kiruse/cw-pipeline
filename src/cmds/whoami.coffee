import { loadConfig } from 'src/config'
import { NetworkOption, getBechPrefix } from 'src/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'whoami'
    .description 'Print the current wallet address.'
    .addOption NetworkOption()
    .action (options) ->
      cfg = await loadConfig options
      key = await cfg.getMnemonicKey()
      console.log key.accAddress getBechPrefix cfg.network
