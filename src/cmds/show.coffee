import { NetworkOption, MainnetOption, getNetworkConfig } from '~/prompting'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  cmd = prog.command 'show'
    .description 'Show information about things.'
  cmd.command 'network'
    .description 'Show information about a network.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (opts) ->
      network = await getNetworkConfig opts
      console.log network
      process.exit 0
