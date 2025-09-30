import { input } from '@inquirer/prompts'
import { isFile } from '~/templating'
import { Cosmos } from '@apophis-sdk/cosmos'
import { CosmWasm } from '@apophis-sdk/cosmwasm'
import { Option } from 'commander'
import fs from 'fs/promises'
import { select } from 'inquirer-select-pro'
import path from 'path'
import YAML from 'yaml'
import { Project } from '~/project'
import { FundsOption, getNetworkConfig, getSigner, inquireEditor, NetworkOption, MainnetOption, parseFunds, inquire } from '~/prompting.js'
import { error, log } from '~/utils.js'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'instantiate'
    .description 'Instantiate a Smart Contract on the blockchain.'
    .option '-m, --msg <path>', 'Path to the YAML file containing the init message. Defaults to msg.init.yml in the current directory.'
    .option '--no-validate', 'Do not validate the init message against the schema. Defaults to validating.'
    .option '-l, --label <label>', 'Label for the contract.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .addOption FundsOption()
    .addArgument '[contract]', 'Contract to instantiate. Can either be a code ID or a name corresponding to a contract in your monorepo.'
    .action (contract, options) ->
      network = await getNetworkConfig options
      signer = await getSigner()
      await signer.connect [network]

      console.log 'Connecting to chain...'
      await Cosmos.ws(network).ready()
      proj = await Project.find().catch(=>)

      codeId = if contract?.match /^[0-9]+$/
        BigInt contract
      else if proj
        unless contract
          contract = await inquire select,
            name: 'contract'
            message: 'Select a contract to instantiate'
            options: (input) =>
              contracts = await proj.getStoredContracts network
              contracts
                .filter (c) -> not input.trim() or c.includes(input.trim())
                .sort()
                .map (c) -> { name: c, value: c }
            multiple: false
        await proj.getLastCodeId network, contract
      else
        error 'Must specify code ID when not in a project'

      {msg, funds} = await proj.getMsg network, contract, 'instantiate'
      error 'No instantiate message found in .cwp/msgs.yml' unless msg
      await proj.validateMsg contract, 'instantiate', msg if options.validate

      funds = parseFunds options.funds ? funds ? []
      admin = options.admin ? signer.address(network)

      label = if options.label
        options.label
      else
        inquire input,
          name: 'label'
          message: 'Enter a label for the contract'

      try
        await log network, "Instantiating contract..."
        addr = await CosmWasm.instantiate { network, signer, codeId, label, admin, msg, funds }
        await proj.addContractAddr network, contract, label, codeId, addr
        console.log "Contract address: #{addr}"
        await log network, "Instantiated contract at #{addr}"
      catch err
        await log network, err
        error 'Failed to instantiate contract:', err
      process.exit 0
