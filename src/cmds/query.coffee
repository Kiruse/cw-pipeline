import { CosmWasm } from '@apophis-sdk/cosmwasm'
import fs from 'fs/promises'
import path from 'path'
import { select } from 'inquirer-select-pro'
import YAML from 'yaml'
import { Project, marshal } from '~/project'
import { getNetworkConfig, inquire, inquireEditor, isAddress, NetworkOption, MainnetOption } from '~/prompting.js'
import { isFile } from '~/templating'
import { error, log } from '~/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'query'
    .description 'Query your Smart Contract on the blockchain.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .option '-m, --msg <path>', 'Path to the YAML file containing the query message. Defaults to msg.query.yml in the current directory.'
    .option '--no-validate', 'Skip query message validation. Messages are validated by default when executing in a Rust project.'
    .argument '[contract]', 'Contract name (if in a project) or address to query. When omitted, prompts for a contract.'
    .argument '[address]', 'Contract address to query. When specified, the given contract is assumed to be of the indicated type.'
    .action (contract, address, opts) ->
      proj = await Project.find()
      network = await getNetworkConfig opts
      error 'Must specify a contract address when not in a project' unless proj

      if isAddress contract
        address = contract
        contract = undefined

      unless contract
        contracts = await proj.getDeployedContracts(network)
        contract = await inquire select,
          name: 'contract'
          message: 'Choose a contract to query'
          options: (input) ->
            contracts
              .filter (c) -> not input.trim() or c.includes(input.trim())
              .sort()
              .map (c) -> { name: c.name, value: c.name }
          multiple: false
      await queryAddress { opts..., contract, address, proj, network }

queryAddress = ({ proj, network, address, contract, opts... }) ->
  tmp = await proj.getDeployedContract(network, contract)
  {contract, name: contractName} = tmp
  address ?= tmp.address

  unless opts.msg
    msgs = await proj.getMsgs contract, 'query'
    error "No query messages found for #{contract} in .cwp/msgs.yml" unless msgs
    opts.msg = await inquire select,
      name: 'msg.query'
      message: 'Choose a prepared query message'
      options: (input) ->
        msgs
          .filter (m) -> not input.trim() or m.includes(input.trim())
          .sort()
          .map (m) -> { name: m, value: m }
      multiple: false
  {msg} = await proj.getMsg({ network }, contract, "query:#{opts.msg}")
  await proj.validateMsg contract, 'query', msg if proj and opts.validate

  report = {
    name: contractName
    contract
    address
    msg
  }
  console.log "Query:\n#{YAML.stringify(marshal(report), { indent: 2 })}"

  try
    result = await CosmWasm.query.smart network, address, msg
    console.log "Response:\n#{YAML.stringify(marshal(result), { indent: 2 })}"
    process.exit 0
  catch err
    await log network, err
    error "Query failed:", err
