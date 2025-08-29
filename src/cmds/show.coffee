import { input } from '@inquirer/prompts'
import { Cosmos } from '@apophis-sdk/cosmos'
import { CosmWasm } from '@apophis-sdk/cosmwasm'
import YAML from 'yaml'
import { drand } from '~/drand'
import { NetworkOption, MainnetOption, getNetworkConfig, inquire } from '~/prompting'

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
      if opts.json
        console.log JSON.stringify network, null, 2
      else
        console.log YAML.stringify network, indent: 2
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

  addDrand cmd

###* @param {import('commander').Command} cmd ###
addDrand = (cmd) ->
  subcmd = cmd.command 'drand'
    .description 'Show information about the Drand Network.'
  subcmd.command 'chains'
    .description 'List the official Drand chains identified by their hashes.'
    .option '--api <url>', 'The URL of the Drand API to use.', 'https://api.drand.sh'
    .action (opts) ->
      res = await drand(opts.api).chains('GET')
      unless Array.isArray(res) and res.find((item) -> typeof item is 'string')
        throw new Error 'Unexpected response from Drand API.'
      console.log res.join '\n'
      process.exit 0
  subcmd.command 'info'
    .description 'Show information about a given Drand chain.'
    .argument '[chain-hash]', 'Hash of the Drand chain to show information for. Will prompt if not specified.'
    .option '--api <url>', 'The URL of the Drand API to use.', 'https://api.drand.sh'
    .option '--json', 'Output as JSON. Useful for post-processing with tools like `jq`.', false
    .action (hash, opts) ->
      hash = hash or await inquire input,
        name: 'drand-chain-hash'
        message: 'Drand chain hash'
        validate: (s) -> s.match(/^[a-fA-F0-9]+$/)? or 'Must be a hex string.'
        options: opts
      res = await drand(opts.api)[hash].info('GET')
      if opts.json
        console.log JSON.stringify res, null, 2
      else
        console.log YAML.stringify res, indent: 2
      process.exit 0
  subcmd.command 'round'
    .description 'Show the latest round of a given Drand chain.'
    .argument '[chain-hash]', 'Hash of the Drand chain to show the latest round for. Will prompt if not specified.'
    .option '-r, --round <number>', 'Round number to show, or \'latest\'.', 'latest'
    .option '--api <url>', 'The URL of the Drand API to use.', 'https://api.drand.sh'
    .option '--json', 'Output as JSON. Useful for post-processing with tools like `jq`.', false
    .action (hash, opts) ->
      hash = hash or await inquire input,
        name: 'drand-chain-hash'
        message: 'Drand chain hash'
        validate: (s) -> s.match(/^[a-fA-F0-9]+$/)? or 'Must be a hex string.'
        options: opts
      opts.round = parseInt(opts.round) unless opts.round is 'latest'

      res = await drand(opts.api)[hash].public[opts.round]('GET')
      if opts.json
        console.log JSON.stringify res, null, 2
      else
        console.log YAML.stringify res, indent: 2
      process.exit 0
