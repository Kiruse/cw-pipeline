import { CosmWasm } from '@apophis-sdk/core/cosmwasm.js'
import { Cosmos } from '@apophis-sdk/core'
import YAML from 'yaml'
import { NetworkOption, MainnetOption, getNetworkConfig } from '~/prompting'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  cmd = prog.command 'show'
    .description 'Show information about things.'
  cmd.command 'network'
    .description 'Show information about a network.'
    .argument '[network]', 'The network to show information about. Prompts if not specified.'
    .addOption MainnetOption()
    .option '--json', 'Output as JSON. Useful for post-processing with tools like `jq`.', false
    .action (network, opts) ->
      network = await getNetworkConfig { opts..., network }
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
  cmd.command 'cw2'
    .description 'Show CW2-standard contract information, if available.'
    .argument '<address>', 'The address of the contract to show.'
    .option '--json', 'Output as JSON. Useful for post-processing with tools like `jq`.', false
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (addr, opts) ->
      network = await getNetworkConfig opts
      res = await CosmWasm.query.contractInfo network, addr
      if opts.json
        console.log JSON.stringify res, null, 2
      else
        console.log "#{res.contract}, v#{res.version}"
      process.exit 0
