import fs from 'fs/promises'
import YAML from 'yaml'
import { loadConfig } from 'src/config'
import { error, getLastContractAddr, getLCD, NetworkOption, validateQueryMsg } from 'src/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'query'
    .description 'Query your Smart Contract on the blockchain.'
    .argument '<msg>', 'Query message in YAML format.'
    .addOption NetworkOption()
    .option '--no-validate', 'Skip query message validation.'
    .option '-c, --contract <address>', 'Address of the contract to query. Defaults to the last contract address in addrs.yml.'
    .action (msgpath, options) ->
      {network} = cfg = await loadConfig options
      addr = options.contract ? await getLastContractAddr network

      lcd = getLCD network

      try
        msg = YAML.parse await fs.readFile(msgpath, 'utf8')
        await validateQueryMsg msg if options.validate
      catch err
        error "Failed to read message. #{err.name}: #{err.message}"

      try
        result = await lcd.wasm.contractQuery addr, msg
      catch err
        console.error err
        error "#{err.name}: #{err.message}"

      console.log YAML.stringify result, indent: 2
