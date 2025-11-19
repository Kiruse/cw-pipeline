import { input } from '@inquirer/prompts'
import { Cosmos } from '@apophis-sdk/cosmos'
import { CosmWasm } from '@apophis-sdk/cosmwasm'
import { select } from 'inquirer-select-pro'
import fs from 'fs/promises'
import path from 'path'
import YAML from 'yaml'
import { drand } from '~/drand'
import { Project } from '~/project'
import { NetworkOption, MainnetOption, getNetworkConfig, inquire } from '~/prompting'
import { collectDenomTraces, collectChannels, collectConnections, collectClients, error, findConnection, findClient, findChainById, getChainDirectory } from '~/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  cmd = prog.command 'show'
    .description 'Show information about things.'
  cmd.command 'account'
    .description 'Show information about a specific account.'
    .argument '<address>', 'The address of the account to show.'
    .option '--json', 'Output as JSON. Useful for post-processing with tools like `jq`.', false
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (address, opts) ->
      network = await getNetworkConfig opts
      { info } = await Cosmos.rest(network).cosmos.auth.v1beta1.account_info[address]('GET')
      if opts.json
        console.log JSON.stringify info, null, 2
      else
        console.log YAML.stringify info, indent: 2
      process.exit 0
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
  addProj cmd
  addIbc cmd

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

###* @param {import('commander').Command} cmd ###
addProj = (cmd) ->
  subcmd = cmd.command 'project'
    .description 'Show information about the current project.'
  subcmd.command 'artifacts'
    .description 'List the contracts in the current project.'
    .addOption NetworkOption()
    .action (opts) ->
      proj = await Project.find()
      files = await fs.readdir path.join(proj.root, 'artifacts')
      files = files
        .filter (f) -> f.endsWith '.wasm'
        .sort()
      console.log YAML.stringify files, { indent: 2 }
      process.exit 0
  subcmd.command 'stored'
    .description 'List the stored contracts in the current project.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (opts) ->
      proj = await Project.find()
      network = await getNetworkConfig opts
      console.log YAML.stringify (await proj.getStoredContracts(network)), { indent: 2 }
      process.exit 0
  subcmd.command 'deployed'
    .description 'List the deployed contracts in the current project.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (opts) ->
      proj = await Project.find()
      network = await getNetworkConfig opts
      contracts = await proj.getDeployedContracts(network)
      contracts = contracts.map (c) -> "#{c.name} (#{c.contract})"
      console.log YAML.stringify contracts, { indent: 2 }
      process.exit 0
  subcmd.command 'contract'
    .description 'Show information about a specific contract in the current project.'
    .argument '[name]', 'The name of the contract to show.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (name, opts) ->
      proj = await Project.find()
      network = await getNetworkConfig opts
      unless name
        contracts = await proj.getDeployedContracts(network)
        contract = await inquire select,
          name: 'contract'
          message: 'Choose a contract'
          options: (input) ->
            contracts
              .filter (c) -> not input.trim() or c.includes(input.trim())
              .sort()
              .map (c) -> { name: c.name, value: c }
          multiple: false
        console.log YAML.stringify contract, { indent: 2 }
      else
        console.log YAML.stringify (await proj.getDeployedContract(network, name)), { indent: 2 }
      process.exit 0

###* @param {import('commander').Command} cmd ###
addIbc = (cmd) ->
  subcmd = cmd.command 'ibc'
    .description 'Show IBC-related information.'
  subcmd.command 'denom-traces'
    .description 'List the IBC denom traces on the current network.'
    .option '--json', 'Output as JSON. Useful for post-processing with tools like `jq`.', false
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (opts) ->
      network = await getNetworkConfig opts
      denomTraces = await collectDenomTraces network
      if opts.json
        console.log JSON.stringify denomTraces, null, 2
      else
        console.log YAML.stringify denomTraces, { indent: 2 }
      process.exit 0
  subcmd.command 'channel'
    .description 'Show information about a specific IBC channel.'
    .argument '[channel]', 'The channel to show information about. Will prompt if not specified.'
    .option '--json', 'Output as JSON. Useful for post-processing with tools like `jq`.', false
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (channel, opts) ->
      network = await getNetworkConfig opts
      channel = channel or await inquire input,
        name: 'channel'
        message: 'IBC channel'
        validate: (s) -> s.match(/^[a-fA-F0-9]+$/)? or 'Must be a hex string.'
        options: opts
      channel = try
        response = await Cosmos.rest(network).ibc.core.channel.v1.channels[channel]('GET')
        response.channel
      catch
        channels = await collectChannels network
        channels.find (c) -> c.channel_id is channel
      if not channel
        error 'Channel not found.'
      # Enrich channel with connection, client, and chain name
      if channel.connection_hops and channel.connection_hops.length > 0
        connectionId = channel.connection_hops[0]
        connection = await findConnection network, connectionId
        if connection
          chainDirectory = await getChainDirectory()
          client = await findClient network, connection.client_id
          if client
            directoryChain = await findChainById client.chain_id, chainDirectory
            channel.client_id = client.client_id
            channel.counterparty.chain_name = directoryChain?.chain_name or 'unknown'
      if opts.json
        console.log JSON.stringify channel, null, 2
      else
        console.log YAML.stringify channel, { indent: 2 }
      process.exit 0
  subcmd.command 'channels'
    .description 'List the IBC channels on the current network.'
    .option '--json', 'Output as JSON. Useful for post-processing with tools like `jq`.', false
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (opts) ->
      network = await getNetworkConfig opts
      channels = await collectChannels network
      if opts.json
        console.log JSON.stringify channels, null, 2
      else
        console.log YAML.stringify channels, { indent: 2 }
      process.exit 0
  subcmd.command 'connection'
    .description 'Show information about a specific IBC connection.'
    .argument '[connection]', 'The connection to show information about. Will prompt if not specified.'
    .option '--json', 'Output as JSON. Useful for post-processing with tools like `jq`.', false
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (connection, opts) ->
      network = await getNetworkConfig opts
      connection = connection or await inquire input,
        name: 'connection'
        message: 'IBC connection'
        validate: (s) -> s.match(/^[a-fA-F0-9]+$/)? or 'Must be a hex string.'
        options: opts
      connection = try
        response = await Cosmos.rest(network).ibc.core.connection.v1.connections[connection]('GET')
        response.connection
      catch
        connections = await collectConnections network
        connections.find (c) -> c.connection_id is connection
      if not connection
        error 'Connection not found.'
      # Enrich connection with client and chain name
      chainDirectory = await getChainDirectory()
      client = await findClient network, connection.client_id
      if client
        directoryChain = await findChainById client.chain_id, chainDirectory
        connection.counterparty.chain_name = directoryChain?.chain_name or 'unknown'
      if opts.json
        console.log JSON.stringify connection, null, 2
      else
        console.log YAML.stringify connection, { indent: 2 }
      process.exit 0
  subcmd.command 'connections'
    .description 'List the IBC connections on the current network.'
    .option '--json', 'Output as JSON. Useful for post-processing with tools like `jq`.', false
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (opts) ->
      network = await getNetworkConfig opts
      connections = await collectConnections network
      if opts.json
        console.log JSON.stringify connections, null, 2
      else
        console.log YAML.stringify connections, { indent: 2 }
      process.exit 0
  subcmd.command 'client'
    .description 'Show information about a specific IBC client.'
    .argument '[client]', 'The client to show information about. Will prompt if not specified.'
    .option '--json', 'Output as JSON. Useful for post-processing with tools like `jq`.', false
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (client, opts) ->
      network = await getNetworkConfig opts
      client = client or await inquire input,
        name: 'client'
        message: 'IBC client'
        validate: (s) -> s.match(/^[a-fA-F0-9]+$/)? or 'Must be a hex string.'
        options: opts
      client = try
        response = await Cosmos.rest(network).ibc.core.client.v1.client_states[client]('GET')
        response.client_state
      catch
        clients = await collectClients network
        clients.find (c) -> c.client_id is client
      if not client
        error 'Client not found.'
      # Enrich client with chain name
      chainDirectory = await getChainDirectory()
      directoryChain = await findChainById client.chain_id, chainDirectory
      client.chain_name = directoryChain?.chain_name or 'unknown'
      if opts.json
        console.log JSON.stringify client, null, 2
      else
        console.log YAML.stringify client, { indent: 2 }
      process.exit 0
  subcmd.command 'clients'
    .description 'List the IBC clients on the current network.'
    .option '--json', 'Output as JSON. Useful for post-processing with tools like `jq`.', false
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (opts) ->
      network = await getNetworkConfig opts
      clients = await collectClients network
      if opts.json
        console.log JSON.stringify clients, null, 2
      else
        console.log YAML.stringify clients, { indent: 2 }
      process.exit 0
