import { CosmWasm } from '@apophis-sdk/core/cosmwasm.js'
import fs from 'fs/promises'
import YAML from 'yaml'
import { error, getLastContractAddr, log } from '~/utils'
import { getNetworkConfig, getSigner, NetworkOption, MainnetOption, FundsOption, parseFunds, validateExecuteMsg } from '~/prompting'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'exec'
    .description 'Execute a Smart Contract on the blockchain.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .addOption FundsOption()
    .option '-c, --contract <address>', 'Address of the contract to execute. Defaults to the last contract address in addrs.yml.'
    .option '-m, --msg <path>', 'Path to the YAML file containing the execute message. Defaults to msg.exec.yml in the current directory.'
    .option '--no-validate', 'Whether to skip message validation. Defaults to validating.'
    .action (options) ->
      network = await getNetworkConfig options
      signer = await getSigner()
      await signer.connect [network]

      addr = options.contract ? await getLastContractAddr network

      msgpath = options.msg ? 'msg.exec.yml'

      msg = try
        YAML.parse((await fs.readFile msgpath, 'utf8').trim()) ? {}
      catch err
        error "Failed to read and/or validate #{msgpath}:", err
      await validateExecuteMsg msg if options.validate

      funds = parseFunds options.funds ? []

      try
        await log network, "Executing contract at #{addr} with message:"
        await log network, msg
        result = await CosmWasm.execute network, signer, addr, CosmWasm.toBinary(msg), funds
        await log network, result
      catch err
        await log network, err
        error "Failed to execute contract:", err
      console.log 'Success! Details have been logged to cw-pipeline.log.'
      process.exit 0
