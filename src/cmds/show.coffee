import { Cosmos } from '@apophis-sdk/core'
import YAML from 'yaml'
import { NetworkOption, MainnetOption, getNetworkConfig } from '~/prompting'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  cmd = prog.command 'show'
    .description 'Show information about things.'
  cmd.command 'network'
    .description 'Show information about a network.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .option '--json', 'Output as JSON. Useful for post-processing with tools like `jq`.', false
    .action (opts) ->
      network = await getNetworkConfig opts
      console.log network
      process.exit 0
  cmd.command 'tx'
    .description 'Show information about a specific transaction.'
    .argument '<hash>', 'The hash of the transaction to show.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (hash, opts) ->
      network = await getNetworkConfig opts
      res = await Cosmos.rest(network).cosmos.tx.v1beta1.txs[hash]('GET')
      if opts.json
        console.log JSON.stringify res, null, 2
      else
        console.log YAML.stringify res, indent: 2
      process.exit 0
