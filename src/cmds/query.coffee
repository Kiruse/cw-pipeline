import { select } from '@inquirer/prompts'
import { CosmWasm } from '@apophis-sdk/cosmwasm'
import fs from 'fs/promises'
import path from 'path'
import YAML from 'yaml'
import { Project } from '~/project'
import { getNetworkConfig, inquire, inquireEditor, isAddress, NetworkOption, MainnetOption } from '~/prompting.js'
import { isFile } from '~/templating'
import { error, log } from '~/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'query'
    .description 'Query your Smart Contract on the blockchain.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .option '-c, --contract <address>', 'Name or address of the contract to query. Deprecated, use positional argument instead.'
    .option '-m, --msg <path>', 'Path to the YAML file containing the query message. Defaults to msg.query.yml in the current directory.'
    .option '--no-validate', 'Skip query message validation. Messages are validated by default when executing in a Rust project.'
    .action (options) ->
      proj = await Project.find()
      network = await getNetworkConfig options
      {contract} = options

      # if an address, regardless of monorepo
      return await queryAddress { proj, network, options... } if isAddress contract
      error 'Must specify a contract address when not in a project' unless proj

      if proj.isMonorepo and not contract
        contract = await inquire select,
          name: 'contract'
          message: 'Choose a contract to query'
          choices: await proj.getContractNames()
      await proj.activate contract if contract

      addr = await proj.getLastContractAddr(network).catch(=>)
      unless addr
        error "No recent address found. Please specify a contract address or deploy a contract first."
      await queryAddress { proj, network, options..., contract: addr }

queryAddress = ({ proj, network, options... }) ->
  msgpath = options.msg ? 'msg.query.yml'
  msgraw = if await isFile msgpath
    await fs.readFile msgpath, 'utf8'
  else
    await inquireEditor
      name: "#{path.basename proj.root}.msg.query"
      message: 'Enter your query message in YAML'
      default: 'enter: yaml'

  msg = try
    YAML.parse(msgraw.trim()) ? {}
  catch err
    error "Failed to read YAML:", err
  await proj.validateMsg msg, 'query' if options.validate

  try
    await log network, "Querying contract at #{options.contract} with message:"
    await log network, msg

    result = await CosmWasm.query.smart network, options.contract, msg
    console.log YAML.stringify result, indent: 2
    await log network, result
    process.exit 0
  catch err
    await log network, err
    error "Query failed:", err
