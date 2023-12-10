import { Option } from 'commander'
import fs from 'fs/promises'
import YAML from 'yaml'
import { error, getChainID, getLCD, getMnemonicKey } from '../utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'instantiate'
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
