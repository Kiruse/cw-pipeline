import { Option } from 'commander'
import { error, findChannel, findConnection, findClient, findChainById, getChainDirectory } from '~/utils'
import { Cosmos, IBC, Bank } from '@apophis-sdk/cosmos'
import { NetworkOption, MainnetOption, getNetworkConfig } from '~/prompting'
import YAML from 'yaml'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  cmd = prog.command 'find'
    .description 'Find things.'
  addIbc cmd

###* @param {import('commander').Command} cmd ###
addIbc = (cmd) ->
  subcmd = cmd.command 'ibc'
    .description 'Find IBC-related information.'
  subcmd.command 'denom-trace'
    .description 'Find a specific IBC denom trace by its base denomination on the source chain.'
    .argument '[denom]', 'Name of the base denomination on the source chain. Will prioritize exact matches, then substring matches. Will prompt if not specified.'
    .option '--json', 'Output as JSON. Useful for post-processing with tools like `jq`.', false
    .option '--no-multihop', 'Only show denom traces that are not multi-hop.'
    .option '--chain <chain-name>', 'Only show denom traces that are on the specified chain.'
    .option '--chain-id <chain-id>', 'Only show denom traces that are on the specified chain ID.'
    .addOption MinSupplyOption()
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (denom, opts) ->
      network = await getNetworkConfig opts
      denomTraces = await collectDenomTraces network
      denomTraces = denomTraces.filter (d) -> d.base_denom is denom or d.base_denom.includes?(denom)
      error 'Denom trace not found.' unless denomTraces.length > 0

      chainDirectory = await getChainDirectory()

      await Cosmos.ws(network).ready()

      denomTraces = await Promise.all denomTraces.map (denomTrace) ->
        segments = getDenomTracePathParts denomTrace.path
        return if not opts.multihop and segments.length > 1
        [port, channel] = segments[0]
        unless port is 'transfer'
          console.error "Unexpected port #{port} while parsing denom trace #{denomTrace.path}/#{denomTrace.base_denom}, expected 'transfer'."
          return

        hash = IBC.hash "#{denomTrace.path}/#{denomTrace.base_denom}"
        supply = await Cosmos.ws(network).query Bank.Query.SupplyOf, denom: "ibc/#{hash}"
        return if supply.amount.amount < opts.minSupply or supply.amount.amount is 0

        channel = await findChannel network, channel
        [connection] = channel.connection_hops

        connection = await findConnection network, connection
        error 'Connection not found.' unless connection

        client = await findClient network, connection.client_id
        error 'Client not found.' unless client

        directoryChain = await findChainById client.chain_id, chainDirectory

        return if opts.chain and directoryChain?.chain_name isnt opts.chain
        return if opts.chain_id and client.chain_id isnt opts.chain_id

        denomTrace.counterparty =
          client_id: connection.client_id
          chain_id: client.chain_id
          chain_name: directoryChain?.chain_name or 'unknown'
          connection_id: connection.id
          channel_id: channel.channel_id
          port: port
        denomTrace.hash = hash
        denomTrace.supply = supply.amount.amount
        denomTrace
      denomTraces = denomTraces.filter Boolean

      if opts.json
        console.log JSON.stringify denomTraces, null, 2
      else
        console.log YAML.stringify denomTraces, { indent: 2 }
      process.exit 0

###* @returns {Promise<import('@apophis-sdk/cosmos/types.sdk.js').IBCTypes.DenomTrace[]>} ###
collectDenomTraces = (network) ->
  response = await Cosmos.rest(network).ibc.apps.transfer.v1.denom_traces('GET')
  allDenomTraces = response.denom_traces
  while response.pagination.next_key
    response = await Cosmos.rest(network).ibc.apps.transfer.v1.denom_traces 'GET',
      query:
        'pagination.key': response.pagination.next_key
    allDenomTraces.push response.denom_traces...
  allDenomTraces
getDenomTracePathParts = (path) ->
  segments = path.split('/')
  groups = []
  for i in [0...segments.length] by 2
    groups.push segments.slice(i, i+2)
  groups

MinSupplyOption = ->
  new Option '--min-supply <amount>', 'Minimum supply on this chain that the denom must have. ' +
      'Note that this value may not be very accurate as it is not possible to query the decimals ' +
      'without tracing the denom back to the source chain.'
    .default '0'
    .argParser (value) -> BigInt(value)
