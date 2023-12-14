import YAML from 'yaml'
import { loadConfig } from 'src/config'
import { NetworkOption, omit } from 'src/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'config'
    .description 'Show current effective configuration - excluding secrets.'
    .addOption NetworkOption()
    .action (options) ->
      cfg = await loadConfig options
      console.log YAML.stringify omit(cfg, 'secrets', 'getMnemonicKey', 'getSecret'), indent: 2
