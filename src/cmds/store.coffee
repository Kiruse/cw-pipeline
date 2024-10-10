import { Cosmos } from '@apophis-sdk/core'
import { CosmWasm } from '@apophis-sdk/core/cosmwasm.js'
import fs from 'fs/promises'
import YAML from 'yaml'
import { getNetworkConfig, getSigner, NetworkOption, MainnetOption } from '~/prompting.js'
import { error, log } from '~/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'store'
    .argument '[filepath]', 'Path to the WASM file to store. Defaults to the only WASM file in the artifacts directory.'
    .description 'Store a Smart Contract on the blockchain.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (filepath, options) ->
      network = await getNetworkConfig options
      signer = await getSigner()
      await signer.connect [network]

      console.log 'Connecting to chain...'
      await Cosmos.ws(network).ready()

      unless filepath
        try
          candidates = (await fs.readdir 'artifacts', withFileTypes: true)
            .filter (entry) -> entry.isFile() and entry.name.endsWith '.wasm'
            .map (entry) -> entry.name
          error 'No WASM files found in artifacts directory.' if candidates.length is 0
          error 'Multiple WASM files found in artifacts directory. Please specify one.' if candidates.length > 1
          filepath = "artifacts/#{candidates[0]}"
        catch
          error 'Failed to read WASM from artifacts.'

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
      await pushCodeIds network, codeId
      process.exit 0

###*
# @param {import('@apophis-sdk/core').NetworkConfig} network
# @param {number} codeIds
###
pushCodeIds = (network, codeId) ->
  await fs.appendFile 'codeIds.yml', '' # essentially touch
  saved = YAML.parse(await fs.readFile 'codeIds.yml', 'utf8') ? {}
  chainId = network.chainId
  saved[chainId] = saved[chainId] ? []
  saved[chainId].push codeId
  await fs.writeFile 'codeIds.yml', YAML.stringify(saved, indent: 2)
