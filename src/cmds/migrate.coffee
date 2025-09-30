import { Cosmos } from '@apophis-sdk/cosmos'
import { CosmWasm } from '@apophis-sdk/cosmwasm'
import { select } from 'inquirer-select-pro'
import { Project } from '~/project'
import { getNetworkConfig, getSigner, NetworkOption, MainnetOption, inquire } from '~/prompting.js'
import { error, log } from '~/utils.js'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'migrate'
    .description 'Migrate a Smart Contract on the blockchain.'
    .argument '[contract]', 'Contract name (if in a project) or address to migrate. When omitted, prompts for a contract name.'
    .option '--code-id <codeId>', 'Code ID to migrate to. When in a project, the code ID will be inferred from the contract name. Rejects if the latest code ID is the same as the current.'
    .option '-m, --msg <path>', 'Path to the YAML file containing the migrate message. Defaults to msg.migrate.yml in the current directory.'
    .option '--no-validate', 'Do not validate the migrate message against the schema. Defaults to validating.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (contract, options) ->
      network = await getNetworkConfig options
      signer = await getSigner()
      await signer.connect [network]

      console.log 'Connecting to chain...'
      await Cosmos.ws(network).ready()
      proj = await Project.find().catch(=>)

      contractName = contract
      contractAddr = contract
      codeId = if codeId?.match /^[0-9]+$/
        BigInt codeId
      else if proj
        unless contract
          contracts = await proj.getDeployedContracts(network)
          {contract, name: contractName, address: contractAddr} = await inquire select,
            name: 'contract'
            message: 'Select a contract to migrate'
            options: (input) ->
              contracts
                .filter (c) -> not input.trim() or c.includes(input.trim())
                .sort()
                .map (c) -> { name: c.name, value: c }
            multiple: false
        await proj.getLastCodeId network, contract
      else
        error 'Must specify code ID when not in a project'

      currentCodeId = await proj?.getCurrentCodeId(network, contractName)
      error 'Latest/specified code ID is identical to current' if currentCodeId is codeId

      {msg} = await proj.getMsg network, contract, 'migrate'
      error 'No migrate message found in .cwp/msgs.yml' unless msg
      await proj.validateMsg contract, 'migrate', msg if options.validate

      unless await confirm "Confirm migration of #{contractAddr} (#{currentCodeId} -> #{codeId})"
        error 'User aborted migration'

      try
        await log network, "Migrating contract..."
        result = await CosmWasm.migrate network, signer, contractAddr, codeId, msg
        console.log "Migration successful"
        await proj.updateContractAddr network, contractAddr, codeId
        await log network, "Migrated contract #{contract} to code ID #{codeId}"
      catch err
        await log network, err
        error 'Failed to migrate contract:', err
      process.exit 0
