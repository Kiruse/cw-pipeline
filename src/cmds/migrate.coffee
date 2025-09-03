import { isFile } from '~/templating'
import { Cosmos } from '@apophis-sdk/cosmos'
import { CosmWasm } from '@apophis-sdk/cosmwasm'
import { Option } from 'commander'
import fs from 'fs/promises'
import path from 'path'
import YAML from 'yaml'
import { Project } from '~/project'
import { getNetworkConfig, getSigner, inquireEditor, NetworkOption, MainnetOption } from '~/prompting.js'
import { error, log } from '~/utils.js'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'migrate'
    .description 'Migrate a Smart Contract on the blockchain.'
    .argument '<contract>', 'Contract address to migrate.'
    .option '-c, --code-id <codeId>', 'Code ID of the Smart Contract to migrate to. Can be a number or a name corresponding to a contract in your monorepo.'
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

      {codeId} = options
      codeId = if codeId?.match /^[0-9]+$/
        BigInt codeId
      else if proj
        await proj.activate codeId
        if proj.isMonorepo and not proj.project
          choice = await inquire select,
            name: 'contract'
            message: 'Select a contract to migrate to'
            choices: await proj.getContractNames()
          await proj.activate choice
        await proj.getLastCodeId network
      else
        error 'Must specify code ID when not in a project'

      msgpath = options.msg ? 'msg.migrate.yml'
      msgraw = if await isFile msgpath
        await fs.readFile msgpath, 'utf8'
      else
        await inquireEditor
          name: "#{path.basename proj.root}.msg.migrate"
          message: 'Enter your migrate message in YAML'
          default: 'enter: yaml'

      msg = try
        YAML.parse(msgraw.trim()) ? {}
      catch err
        error "Failed to read YAML:", err
      await proj.validateMsg msg, 'migrate' if options.validate

      try
        await log network, "Migrating contract..."
        result = await CosmWasm.migrate network, signer, contract, codeId, msg
        console.log "Migration successful"
        await log network, "Migrated contract #{contract} to code ID #{codeId}"
      catch err
        await log network, err
        error 'Failed to migrate contract:', err
      process.exit 0
