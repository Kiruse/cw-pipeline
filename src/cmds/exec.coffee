import { isFile } from '~/templating'
import { CosmWasm } from '@apophis-sdk/cosmwasm'
import fs from 'fs/promises'
import YAML from 'yaml'
import { Project } from '~/project'
import { getNetworkConfig, getSigner, NetworkOption, MainnetOption, FundsOption, parseFunds, isAddress, inquireEditor } from '~/prompting'
import { error, log } from '~/utils'

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
      proj = await Project.find().catch(=>)

      # if an address, regardless of monorepo
      return await execAddress { proj, network, options... } if isAddress options.contract
      error 'Must specify a contract address when not in a project' unless proj

      if proj.isMonorepo and not options.contract
        options.contract = await inquire select,
          name: 'contract'
          message: 'Choose a contract to execute'
          choices: await proj.getContractNames()
      await proj.activate options.contract if options.contract

      addr = options.contract ? await proj.getLastContractAddr(network).catch(=>)
      unless addr
        error "No recent address found. Please specify a contract address or deploy a contract first."
      await execAddress { proj, network, options..., contract: addr }

execAddress = ({ proj, network, options... }) ->
  signer = await getSigner()
  await signer.connect [network]

  msgpath = options.msg ? 'msg.exec.yml'
  msgraw = if await isFile msgpath
    await fs.readFile msgpath, 'utf8'
  else
    await inquireEditor
      name: "#{path.basename proj.root}.msg.exec"
      message: 'Enter your execute message in YAML'
      default: 'enter: yaml'

  msg = try
    YAML.parse(msgraw.trim()) ? {}
  catch err
    error "Failed to read YAML:", err
  await proj.validateMsg msg, 'execute' if options.validate

  funds = parseFunds options.funds ? []

  try
    await log network, "Executing contract at #{options.contract} with message:"
    await log network, msg

    result = await CosmWasm.execute network, signer, options.contract, msg, funds
    await log network, result
    console.log 'Success! Details have been logged to cw-pipeline.log.'
    process.exit 0
  catch err
    await log network, err
    error "Failed to execute contract:", err
