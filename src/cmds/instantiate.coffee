import { loadConfig } from 'src/config'
import { MsgInstantiateContract } from '@terra-money/feather.js/src'
import { Option } from 'commander'
import fs from 'fs/promises'
import YAML from 'yaml'
import { error, getChainID, getLCD, getNetwork, NetworkOption, logResult, getLogs } from '../utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'instantiate'
    .description 'Instantiate a Smart Contract on the blockchain.'
    .argument '[codeId]', 'Code ID of the Smart Contract to instantiate. If omitted, takes the last code ID from codeIds.txt. Fails if none such.'
    .option '-m, --init-msg <path>', 'Path to the YAML file containing the init message. When omitted, prompts for input based on the contract\'s schema.'
    .addOption(
      new Option '-l, --label <label>', 'Label for the contract. Defaults to a generic label, but I recommend setting one for legibility.'
        .default 'Generic Contract'
    )
    .addOption NetworkOption()
    .action (codeId, options) ->
      {network} = cfg = await loadConfig options

      codeId = await getLastCodeId network unless codeId
      codeId = Number codeId
      try
        initMsg = if options.initMsg
          YAML.parse (await fs.readFile options.initMsg, 'utf8').trim()
        else
          await inquireInitMsg()
      catch
        error 'Failed to read init message.'

      chainId = getChainID network
      lcd = getLCD network
      wallet = lcd.wallet await cfg.getSecret 'mnemonic'
      addr = wallet.key.accAddress 'terra'

      try
        tx = await wallet.createAndSignTx
          msgs: [new MsgInstantiateContract addr, addr, codeId, initMsg, [], options.label]
          chainID: chainId
      catch err
        console.error "#{err.name}: #{err.message}"
        if err.isAxiosError
          console.error YAML.stringify err.response.data
        process.exit 1

      result = await lcd.tx.broadcast tx, chainId
      error 'Error:', result.raw_log if result.code

      await logResult result, network

      logs = getLogs result
      error 'No logs' if logs.length is 0
      addrs = logs[0].eventsByType.instantiate?._contract_address
      error 'No contract addresses found' unless addrs?.length

      await pushContractAddrs network, codeId, addrs

      console.log "Contract addresses: #{addrs.join ', '}"

getLastCodeId = (network) ->
  try
    doc = YAML.parse (await fs.readFile 'codeIds.yml', 'utf8').trim()
    codeIds = doc[getNetwork network]
    error 'No code IDs found' unless codeIds?.length
    BigInt codeIds[codeIds.length - 1]
  catch
    error 'Failed to read code IDs. Ensure "codeIds.yml" exists and is valid, or manually specify the code ID.'

inquireInitMsg = ->
  error 'message helper not yet implemented'

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
