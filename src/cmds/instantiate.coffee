import { isFile } from '~/templating'
import { Cosmos } from '@apophis-sdk/core'
import { CosmWasm } from '@apophis-sdk/core/cosmwasm.js'
import { Option } from 'commander'
import fs from 'fs/promises'
import YAML from 'yaml'
import { Project } from '~/project'
import { getNetworkConfig, getSigner, NetworkOption, MainnetOption, parseFunds, FundsOption } from '~/prompting.js'
import { error, log } from '~/utils.js'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'instantiate'
    .description 'Instantiate a Smart Contract on the blockchain.'
    .argument '<label>', 'Label for the contract. For every user and code ID, this must be unique. For the sake of your fellow developers, please choose a meaningful label.'
    .option '-c, --code-id <codeId>', 'Code ID of the Smart Contract to instantiate. Can be a number or a name corresponding to a contract in your monorepo.'
    .option '-m, --msg <path>', 'Path to the YAML file containing the init message. Defaults to msg.init.yml in the current directory.'
    .option '--no-validate', 'Do not validate the init message against the schema. Defaults to validating.'
    .addOption(
      new Option '-l, --label <label>', 'Label for the contract. Defaults to a generic label, but I recommend setting one for legibility.'
        .default 'Generic Contract'
    )
    .addOption NetworkOption()
    .addOption MainnetOption()
    .addOption FundsOption()
    .action (label, options) ->
      network = await getNetworkConfig options
      signer = await getSigner()
      await signer.connect [network]

      console.log 'Connecting to chain...'
      await Cosmos.ws(network).ready()
      proj = await Project.find().catch(=>)

      {codeId} = options
      codeId = if codeId?.match /^[0-9]+$/
        BigInt codeId
      else if proj
        await proj.activate codeId
        if proj.isMonorepo and not proj.project
          choice = await inquire select,
            name: 'contract'
            message: 'Select a contract to instantiate'
            choices: await proj.getContractNames()
          await proj.activate choice
        await proj.getLastCodeId network
      else
        error 'Must specify code ID when not in a project'

      msgpath = options.msg ? 'msg.init.yml'
      msgraw = if await isFile msgpath
        await fs.readFile msgpath, 'utf8'
      else
        await inquireEditor
          name: "#{path.basename proj.root}.msg.init"
          message: 'Enter your init message in YAML'
          default: 'enter: yaml'

      msg = try
        YAML.parse(msgraw.trim()) ? {}
      catch err
        error "Failed to read YAML:", err
      await proj.validateMsg msg, 'instantiate' if options.validate

      funds = parseFunds options.funds ? []
      admin = options.admin ? signer.address(network)

      try
        await log network, "Instantiating contract..."
        addr = await CosmWasm.instantiate { network, signer, codeId, label, admin, msg: CosmWasm.toBinary(msg), funds }
        await proj.addContractAddr network, codeId, addr
        console.log "Contract address: #{addr}"
        await log network, "Instantiated contract at #{addr}"
      catch err
        await log network, err
        error 'Failed to instantiate contract:', err
      process.exit 0
