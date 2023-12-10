import { MsgStoreCode, MsgInstantiateContract } from '@terra-money/feather.js/src'
import { error, getLCD, getMnemonicKey, getChainID, getLogs, getLogTimestamp } from './utils'
import { Command, Option } from 'commander'
import fs from 'fs/promises'
import YAML from 'yaml'

unless process.env.VERSION
  throw Error 'VERSION environment variable not set.'

program = new Command 'cw-pipeline'
program.version process.env.VERSION

program.command 'store'
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

    logs = getLogs result
    error 'No logs' if logs.length is 0
    codeIds = logs[0].eventsByType.store_code?.code_id?.map (scode) -> BigInt scode
    error 'No code IDs found' if codeIds.length is 0

    await fs.appendFile 'codeIds.txt', codeIds.map((id) -> "#{id}\n").join ''
    await fs.appendFile 'cw-pipeline.log', [
      "[#{getLogTimestamp()}]\n"
      YAML.stringify(result, indent: 2) + '\n\n'
    ].join ''

    console.log "Code IDs: #{codeIds.join ', '}"
program.command 'instantiate'
  .argument '<codeId>', 'Code ID of the Smart Contract to instantiate.'
  .argument '<initMsgFile>', 'Path to the YAML file containing the init message.'
  .description 'Instantiate a Smart Contract on the blockchain.'
  .addOption(
    new Option '-n, --network <network>', 'Network to use. Defaults to "testnet".'
      .choices ['mainnet', 'testnet']
  )
  .action ->
    [codeId, initMsgFile] = this.args
    options = this.opts()
    error 'Missing code ID' unless codeId
    error 'Missing message file' unless initMsgFile

    chainId = getChainID options.network
    lcd = getLCD options.network
    wallet = lcd.wallet await getMnemonicKey()
    addr = wallet.key.accAddress 'terra'

    initMsg = YAML.parse await fs.readFile initMsgFile, 'utf8'
    tx = await wallet.createAndSignTx
      msgs: [new MsgInstantiateContract addr, addr, codeId, JSON.stringify(initMsg)]
      chainID: chainId

    result = await lcd.tx.broadcast tx, chainId
    error 'Error:', result.raw_log if result.code
    console.log YAML.stringify result, indent: 2

program.parse()
