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

pushCodeIds = (network, codeIds) ->
  await fs.appendFile 'codeIds.yml', '' # essentially touch
  saved = YAML.parse(await fs.readFile 'codeIds.yml', 'utf8') ? {}
  prop = switch network
    when 'mainnet' then 'terra2'
    when 'testnet' then 'terra2-testnet'
    else error 'Invalid network'
  saved[prop] = saved[prop] ? []
  saved[prop].push codeIds...
  await fs.writeFile 'codeIds.yml', YAML.stringify(saved, indent: 2)
