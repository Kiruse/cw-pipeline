import { error } from '~/utils'
import { toBase64, toUtf8 } from '@apophis-sdk/core/utils.js'
import { CosmWasm } from '@apophis-sdk/cosmwasm'
import { confirm, input } from '@inquirer/prompts'
import chalk from 'chalk'
import { Option } from 'commander'
import * as YAML from 'yaml'
import { NetworkOption, MainnetOption, getNetworkConfig, inquire, isAddress } from '~/prompting'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  cmd = prog.command 'state'
    .description 'Read and search the state of a CosmWasm smart contract.'
  cmd.command 'enumerate'
    .description [
      'Enumerate all the keys in the contract\'s state. This is a rather unsophisticated '
      'command and will be complemented by more sophisticated options and siblings in the future. '
      'All values are shown in base64 encoding as the meaning of these values is entirely '
      'contract-specific.'
    ].join ''
    .argument '[address]', 'The address of the contract to enumerate. Will prompt if not specified.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (address, opts) ->
      network = await getNetworkConfig opts
      address = address or await inquire input,
        name: 'address'
        message: 'Contract address'
        validate: (value) -> isAddress(value) or 'Invalid address'

      nextKey = undefined
      more = true
      while more and (nextKey or nextKey is undefined)
        res = await CosmWasm.query.state network, address, nextKey
        for item in res.items
          console.log "#{chalk.green item.keypath.join '.'}: #{chalk.yellow toBase64 item.value}"
        nextKey = res.pagination.next_key
        more = nextKey and await confirm
          message: if res.pagination.total then "#{res.pagination.total} total. Load more?" else 'Load more?'
          default: true
      process.exit 0
  cmd.command 'show'
    .description 'Show the value of a contract state key.'
    .argument '[keys...]', 'The keys to show the value of. If not specified, will prompt for a key.'
    .option '-c, --contract [address]', 'The address of the contract to show the state of. Will prompt if not specified.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .addOption(
      new Option('--as <type>', 'The type to show the value as. Defaults to base64.')
        .default 'base64'
        .choices ['base64', 'hex', 'json', 'yaml', 'bigint-be', 'bigint-le']
    ).action (keys, opts) ->
      network = await getNetworkConfig opts
      address = opts.contract or await inquire input,
        name: 'address'
        message: 'Contract address'
        validate: (value) -> isAddress(value) or 'Invalid address'

      unless keys.length
        res = await inquire input,
          name: 'state-key'
          message: 'State keypath'
          default: 'space-separated list of keys'
        keys = res.split ' '

      res = await CosmWasm.query.raw network, address, keys
      if res is null
        error 'No value found at the specified keypath.'

      switch opts.as
        when 'base64'
          console.log toBase64 res
        when 'hex'
          console.log toHex res
        when 'json'
          res = JSON.parse toUtf8 res
          console.log JSON.stringify res, null, 2
        when 'yaml'
          res = JSON.parse toUtf8 res
          console.log YAML.stringify res, indent: 2
        when 'bigint-be', 'bigint-le'
          console.log toBigInt res, opts.as.endsWith 'le'
      process.exit 0

###* @param {Uint8Array} value ###
toBigInt = (value, big = true) ->
  res = 0n
  dataview = new DataView value.buffer
  offset = 0
  while offset < value.byteLength
    if big
      res = res + (dataview.getUint64(offset, true) << (offset * 64))
    else
      res = (res << 64) + dataview.getUint64(offset, false)
    offset += 8
  res
