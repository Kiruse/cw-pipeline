import { CosmWasm } from '@apophis-sdk/core/cosmwasm.js'
import { Option } from 'commander'
import fs from 'fs/promises'
import YAML from 'yaml'
import { getNetworkConfig, getSigner, NetworkOption, MainnetOption, validateInitMsg } from '~/prompting.js'
import { error, log } from '~/utils.js'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'instantiate'
    .description 'Instantiate a Smart Contract on the blockchain.'
    .argument '[codeId]', 'Code ID of the Smart Contract to instantiate. If omitted, takes the last code ID from codeIds.txt. Fails if none such.'
    .option '-m, --msg <path>', 'Path to the YAML file containing the init message. Defaults to msg.init.yml in the current directory.'
    .option '--no-validate', 'Do not validate the init message against the schema. Defaults to validating.'
    .addOption(
      new Option '-l, --label <label>', 'Label for the contract. Defaults to a generic label, but I recommend setting one for legibility.'
        .default 'Generic Contract'
    )
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (codeId, options) ->
      network = await getNetworkConfig options
      signer = await getSigner()

      codeId = await getLastCodeId network unless codeId
      codeId = BigInt codeId
      try
        msg = YAML.parse (await fs.readFile options.msg ? 'msg.init.yml', 'utf8').trim()
        await validateInitMsg msg if options.validate
      catch err
        error 'Failed to read and/or validate init message:', err

      funds = options.funds ? []
      admin = options.admin ? signer.address(network)

      try
        await log network, "Instantiating contract..."
        addr = await CosmWasm.instantiate { network, signer, codeId, label, admin, msg, funds }
        await pushContractAddrs network, codeId, [addr]
        console.log "Contract address: #{addr}"
        await log network, "Instantiated contract at #{addr}"
      catch err
        await log network, err
        error 'Failed to instantiate contract:', err

getLastCodeId = (network) ->
  try
    doc = YAML.parse (await fs.readFile 'codeIds.yml', 'utf8').trim()
    codeIds = doc[getNetwork network]
    error 'No code IDs found' unless codeIds?.length
    BigInt codeIds[codeIds.length - 1]
  catch
    error 'Failed to read code IDs. Ensure "codeIds.yml" exists and is valid, or manually specify the code ID.'

pushContractAddrs = (network, codeId, addrs) ->
  await fs.appendFile 'addrs.yml', '' # essentially touch
  saved = YAML.parse(await fs.readFile 'addrs.yml', 'utf8') ? {}
  network = getNetwork network
  saved[network] = saved[network] ? []
  for addr in addrs
    saved[network].push
      address: addr
      codeId: codeId
  await fs.writeFile 'addrs.yml', YAML.stringify saved, indent: 2
