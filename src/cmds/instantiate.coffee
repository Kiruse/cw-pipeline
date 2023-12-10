import { renderSubProgram } from '../ink-utils'
import { Option } from 'commander'
import fs from 'fs/promises'
import YAML from 'yaml'
import { error, getChainID, getLCD, getMnemonicKey } from '../utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'instantiate'
    .description 'Instantiate a Smart Contract on the blockchain.'
    .argument '[codeId]', 'Code ID of the Smart Contract to instantiate. If omitted, takes the last code ID from codeIds.txt. Fails if none such.'
    .option '-m, --init-msg', 'Path to the YAML file containing the init message. When omitted, prompts for input based on the contract\'s schema.'
    .addOption(
      new Option '-n, --network <network>', 'Network to use. Defaults to "testnet".'
        .choices ['mainnet', 'testnet']
    )
    .action ->
      [codeId, initMsgFile] = this.args
      options = this.opts()

      codeId = await getLastCodeId() unless codeId
      try
        initMsgFile = if initMsgFile
          await fs.readFile initMsgFile, 'utf8'
        else
          await getInitMsgFile() unless initMsgFile
      catch
        error 'Failed to read init message.'

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

getLastCodeId = ->
  try
    codeIds = (await fs.readFile 'codeIds.txt', 'utf8').trim().split('\n').map (line) -> BigInt line.trim()
    error 'No code IDs found' if codeIds.length is 0
    codeIds[codeIds.length - 1]
  catch
    error 'Failed to read code IDs.'

getInitMsgFile = ->
  error 'message helper not yet implemented'
  await renderSubProgram InquireInitMsgProgram
