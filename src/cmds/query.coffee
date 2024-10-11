import { CosmWasm } from '@apophis-sdk/core/cosmwasm.js'
import fs from 'fs/promises'
import YAML from 'yaml'
import { getNetworkConfig, NetworkOption, MainnetOption, validateQueryMsg } from '~/prompting.js'
import { error, getLastContractAddr } from '~/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'query'
    .description 'Query your Smart Contract on the blockchain.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .option '-c, --contract <address>', 'Address of the contract to query. Defaults to the last contract address in addrs.yml.'
    .option '-m, --msg <path>', 'Path to the YAML file containing the query message. Defaults to msg.query.yml in the current directory.'
    .option '--no-validate', 'Skip query message validation. Defaults to validating.'
    .action (options) ->
      network = await getNetworkConfig options
      addr = options.contract ? await getLastContractAddr network

      msgpath = options.msg ? 'msg.query.yml'

      msg = try
        YAML.parse((await fs.readFile msgpath, 'utf8').trim()) ? {}
      catch err
        error "Failed to read and/or validate #{msgpath}:", err
      await validateQueryMsg msg if options.validate

      try
        await log network, "Querying contract at #{addr} with message:"
        await log network, msg

        result = await CosmWasm.query.smart network, addr, CosmWasm.toBinary(msg)
        console.log YAML.stringify result, indent: 2
        await log network, result
      catch err
        await log network, err
        error "Query failed:", err
      process.exit 0
