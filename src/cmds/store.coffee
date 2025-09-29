import { Cosmos } from '@apophis-sdk/cosmos'
import { CosmWasm } from '@apophis-sdk/cosmwasm'
import fs from 'fs/promises'
import { select } from 'inquirer-select-pro'
import path from 'path'
import { Project } from '~/project'
import { getNetworkConfig, getSigner, NetworkOption, MainnetOption, getContractFromPath, inquire } from '~/prompting.js'
import { isFile } from '~/templating'
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
        files = await fs.readdir path.join(proj.root, 'artifacts')
        files = files.filter (f) -> f.endsWith '.wasm'
        await inquire select,
          name: 'artifact'
          message: 'Choose an artifact'
          options: (input) ->
            files
              .filter (f) -> not input or f.includes(input)
              .sort()
              .map (f) -> { name: f.replace(/\.wasm$/, ''), value: path.join(proj.root, 'artifacts', f) }
          multiple: false
      else
        error "Must specify a WASM file when not in a Rust project" unless contract
        error "Not in a Rust project, and no WASM file found at #{path.resolve contract}"
      contract = getContractFromPath filepath

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
      await proj.addCodeId network, contract, codeId if proj
      process.exit 0
