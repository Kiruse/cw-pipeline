import { select } from '@inquirer/prompts'
import { getFiles, isFile } from '~/templating'
import { Cosmos } from '@apophis-sdk/cosmos'
import { CosmWasm } from '@apophis-sdk/cosmwasm'
import fs from 'fs/promises'
import path from 'path'
import { Project } from '~/project'
import { getNetworkConfig, getSigner, NetworkOption, MainnetOption, inquire } from '~/prompting.js'
import { error, log } from '~/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'store'
    .argument '[contract]', 'Path to the WASM file to store. Defaults to the only WASM file in the artifacts directory. Can also be a contract name in a monorepo.'
    .description 'Store a Smart Contract on the blockchain.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (contract, options) ->
      network = await getNetworkConfig options
      signer = await getSigner()
      await signer.connect [network]
      proj = await Project.find().catch(=>)

      console.log 'Connecting to chain...'
      await Cosmos.ws(network).ready()

      filepath = if await isFile contract
        contract
      else if proj
        await proj.activate contract
        if proj.isMonorepo
          unless proj.project
            choice = await inquire select,
              name: 'contract'
              message: 'Select a contract to upload & store'
              choices: await proj.getContractNames()
            await proj.activate choice
          path.join proj.projectRoot, 'artifacts', "#{contract}.wasm"
        else
          files = (await getFiles 'artifacts').filter (f) -> f.endsWith '.wasm'
          error 'No WASM files found in artifacts directory.' if files.length is 0
          error 'Multiple WASM files found in artifacts directory. Please specify one.' if files.length > 1
          files[0]
      else
        error "Must specify a WASM file when not in a Rust project" unless contract
        error "Not in a Rust project, and no WASM file found at #{path.resolve contract}"

      bytecode = Uint8Array.from(await fs.readFile(filepath))

      try
        await log network, "Storing code..."
        console.log "Storing code on #{network.name} (#{network.chainId})..."
        codeId = await CosmWasm.store network, signer, bytecode
      catch err
        await log network, err
        error "Failed to store code on-chain:", err

      console.log "Code ID: #{codeId}"
      await log network, "codeId: #{codeId}"
      await proj.addCodeId network, codeId
      process.exit 0
