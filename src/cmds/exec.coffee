import { MsgExecuteContract } from '@terra-money/feather.js'
import { Option } from 'commander'
import fs from 'fs/promises'
import YAML from 'yaml'
import { loadConfig } from 'src/config'
import {
  error,
  getBechPrefix,
  getChainID,
  getLastContractAddr,
  getLCD,
  logResult,
  NetworkOption,
  validateExecuteMsg,
} from 'src/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'exec'
    .description 'Execute a Smart Contract on the blockchain.'
    .argument '<msg>', 'Path to the YAML file containing the message to execute.'
    .addOption NetworkOption()
    .option '-c, --contract <address>', 'Address of the contract to execute. Defaults to the last contract address in addrs.yml.'
    .addOption (
      new Option '-g, --gas <amount>', 'Amount of gas to use. Defaults to 300000.'
        .default 'auto'
    )
    .action (msgpath, options) ->
      {network} = cfg = await loadConfig options
      addr = options.contract ? await getLastContractAddr network

      chainId = getChainID network
      lcd = getLCD network
      wallet = lcd.wallet await cfg.getMnemonicKey()
      sender = wallet.key.accAddress getBechPrefix network

      msg = YAML.parse await fs.readFile msgpath, 'utf8'
      await validateExecuteMsg msg

      try
        tx = await wallet.createAndSignTx
          msgs: [new MsgExecuteContract sender, addr, msg]
          chainID: chainId
          gas: options.gas
      catch err
        error "#{err.name}: #{err.message}"

      result = await lcd.tx.broadcast tx, chainId
      error 'Error:', result.raw_log if result.code
      await logResult result, network
      console.log 'Success! Check cw-pipeline.log for details.'
