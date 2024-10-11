import { Cosmos } from '@apophis-sdk/core'
import { CosmWasm } from '@apophis-sdk/core/cosmwasm.js'
import { Option } from 'commander'
import fs from 'fs/promises'
import YAML from 'yaml'
import { getNetworkConfig, getSigner, NetworkOption, MainnetOption, validateInitMsg, parseFunds, FundsOption } from '~/prompting.js'
import { error, log } from '~/utils.js'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'instantiate'
    .description 'Instantiate a Smart Contract on the blockchain.'
    .argument '<label>', 'Label for the contract. For every user and code ID, this must be unique. For the sake of your fellow developers, please choose a meaningful label.'
    .argument '[codeId]', 'Code ID of the Smart Contract to instantiate. If omitted, takes the last code ID from codeIds.txt. Fails if none such.'
    .option '-m, --msg <path>', 'Path to the YAML file containing the init message. Defaults to msg.init.yml in the current directory.'
    .option '--no-validate', 'Do not validate the init message against the schema. Defaults to validating.'
    .addOption(
      new Option '-l, --label <label>', 'Label for the contract. Defaults to a generic label, but I recommend setting one for legibility.'
        .default 'Generic Contract'
    )
    .addOption NetworkOption()
    .addOption MainnetOption()
    .addOption FundsOption()
    .action (label, codeId, options) ->
      network = await getNetworkConfig options
      signer = await getSigner()
      await signer.connect [network]

      console.log 'Connecting to chain...'
      await Cosmos.ws(network).ready()

      msgpath = options.msg ? 'msg.init.yml'

      codeId = await getLastCodeId network unless codeId
      codeId = BigInt codeId
      msg = try
        YAML.parse((await fs.readFile msgpath, 'utf8').trim()) ? {}
      catch err
        error "Failed to read #{msgpath}:", err
      await validateInitMsg msg if options.validate

      funds = parseFunds options.funds ? []
      admin = options.admin ? signer.address(network)

      try
        await log network, "Instantiating contract..."
        addr = await CosmWasm.instantiate { network, signer, codeId, label, admin, msg: CosmWasm.toBinary(msg), funds }
        await pushContractAddr network, codeId, addr
        console.log "Contract address: #{addr}"
        await log network, "Instantiated contract at #{addr}"
      catch err
        await log network, err
        error 'Failed to instantiate contract:', err
      process.exit 0

###* @param {import('@apophis-sdk/core').NetworkConfig} network ###
getLastCodeId = (network) ->
  try
    doc = YAML.parse (await fs.readFile 'codeIds.yml', 'utf8').trim()
    codeIds = doc[network.name]
    error 'No code IDs found' unless codeIds?.length
    BigInt codeIds[codeIds.length - 1]
  catch
    error 'Failed to read code IDs. Ensure "codeIds.yml" exists and is valid, or manually specify the code ID.'

###*
# @param {import('@apophis-sdk/core').NetworkConfig} network
# @param {number} codeId
# @param {string} address
###
pushContractAddr = (network, codeId, address) ->
  await fs.appendFile 'addrs.yml', '' # essentially touch
  saved = YAML.parse(await fs.readFile 'addrs.yml', 'utf8') ? {}
  saved[network.name] = saved[network.name] ? []
  saved[network.name].push { address, codeId }
  await fs.writeFile 'addrs.yml', YAML.stringify saved, indent: 2
