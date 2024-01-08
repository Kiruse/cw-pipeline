import { loadConfig } from 'src/config'
import { MsgStoreCode } from '@terra-money/feather.js'
import fs from 'fs/promises'
import YAML from 'yaml'
import { error, getChainID, getLCD, getLogs, NetworkOption, logResult, getBechPrefix } from '../utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'store'
    .argument '[filepath]', 'Path to the WASM file to store. Defaults to the only WASM file in the artifacts directory.'
    .description 'Store a Smart Contract on the blockchain.'
    .addOption NetworkOption()
    .action (filepath, options) ->
      {network} = cfg = await loadConfig options
      unless filepath
        try
          candidates = (await fs.readdir 'artifacts', withFileTypes: true)
            .filter (entry) -> entry.isFile() and entry.name.endsWith '.wasm'
            .map (entry) -> entry.name
          error 'No WASM files found in artifacts directory.' if candidates.length is 0
          error 'Multiple WASM files found in artifacts directory. Please specify one.' if candidates.length > 1
          filepath = "artifacts/#{candidates[0]}"
        catch
          error 'Failed to read WASM from artifacts.'

      chainId = getChainID network
      lcd = getLCD network
      wallet = lcd.wallet await cfg.getMnemonicKey()
      addr = wallet.key.accAddress getBechPrefix network
      bytecode = (await fs.readFile(filepath)).toString('base64')

      try
        tx = await wallet.createAndSignTx
          msgs: [new MsgStoreCode addr, bytecode]
          chainID: chainId
      catch err
        if err.isAxiosError
          console.error "AxiosError #{err.response.status}"
          console.error YAML.stringify err.response.data, indent: 2
        else
          console.error "#{err.name}: #{err.message}"
        error 'Failed to create transaction.'

      result = await lcd.tx.broadcast tx, chainId
      error 'Error:', result.raw_log if result.code

      await logResult result, network

      logs = getLogs result
      error 'No logs' if logs.length is 0
      codeIds = logs[0].eventsByType.store_code?.code_id?.map (scode) -> BigInt scode
      error 'No code IDs found' unless codeIds?.length

      await pushCodeIds network, codeIds

      console.log "Code IDs: #{codeIds.join ', '}"

pushCodeIds = (network, codeIds) ->
  await fs.appendFile 'codeIds.yml', '' # essentially touch
  saved = YAML.parse(await fs.readFile 'codeIds.yml', 'utf8') ? {}
  prop = switch network
    when 'mainnet' then 'terra2'
    when 'testnet' then 'terra2-testnet'
    else error 'Invalid network'
  saved[prop] = saved[prop] ? []
  saved[prop].push codeIds...
  await fs.writeFile 'codeIds.yml', YAML.stringify(saved, indent: 2)
