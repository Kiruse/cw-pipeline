import { Option } from 'commander'
import fs from 'fs/promises'
import YAML from 'yaml'
import { error, getChainID, getLCD, getMnemonicKey } from '../utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'store'
    .argument '[filepath]', 'Path to the WASM file to store. Defaults to the only WASM file in the artifacts directory.'
    .description 'Store a Smart Contract on the blockchain.'
    .addOption(
      new Option '-n, --network <network>', 'Network to use. Defaults to "testnet".'
        .choices ['mainnet', 'testnet']
    )
    .action ->
      [filepath] = this.args
      options = this.opts()
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

      chainId = getChainID options.network
      lcd = getLCD options.network
      wallet = lcd.wallet await getMnemonicKey()
      bytecode = (await fs.readFile(filepath)).toString('base64')

      try
        tx = await wallet.createAndSignTx
          msgs: [new MsgStoreCode wallet.key.accAddress('terra'), bytecode]
          chainID: chainId
      catch err
        if err.isAxiosError
          console.error "AxiosError #{err.response.status}"
          console.error YAML.stringify err.response.data, indent: 2
        error 'Failed to create transaction.'

      result = await lcd.tx.broadcast tx, chainId
      error 'Error:', result.raw_log if result.code

      await fs.appendFile 'cw-pipeline.log', [
        "[#{getLogTimestamp()}]\n"
        YAML.stringify(result, indent: 2) + '\n\n'
      ].join ''

      logs = getLogs result
      error 'No logs' if logs.length is 0
      codeIds = logs[0].eventsByType.store_code?.code_id?.map (scode) -> BigInt scode
      error 'No code IDs found' if codeIds.length is 0

      await pushCodeIds codeIds

      console.log "Code IDs: #{codeIds.join ', '}"

pushCodeIds = (codeIds) ->
  saved = YAML.parse await fs.readFile 'codeIds.yml', 'utf8'
  prop = switch options.network
    when 'mainnet' then 'terra2'
    when 'testnet' then 'terra2-testnet'
    else error 'Invalid network'
  saved[prop] = saved[prop] ? []
  saved[prop].push codeIds...
  await fs.writeFile 'codeIds.yml', YAML.stringify(saved, indent: 2)
