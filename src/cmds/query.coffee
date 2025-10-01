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
    .action (contract, opts) ->
      proj = await Project.find()
      network = await getNetworkConfig opts

      return await queryAddress { opts..., contract, proj, network } if isAddress contract
      error 'Must specify a contract address when not in a project' unless proj

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
      await queryAddress { opts..., contract, proj, network }

queryAddress = ({ proj, network, contract, opts... }) ->
  contractName = contract
  {msg, addr} = if isAddress contract
    error 'Msg must be a filepath when querying on a contract address' unless await isFile opts.msg
    msgraw = await fs.readFile opts.msg, 'utf8'
    msg = YAML.parse(msgraw.trim()) ? {}
    { msg, addr: contract }
  else
    {address: addr, contract, name: contractName} = await proj.getDeployedContract(network, contract)
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
    data = await proj.getMsg({ network }, contract, "query:#{opts.msg}")
    { data..., addr }
  await proj.validateMsg contract, 'query', msg if proj and opts.validate

  report = {
    name: contractName
    contract
    addr
    msg
  }
  console.log "Query:\n#{YAML.stringify(marshal(report), { indent: 2 })}"

  try
    result = await CosmWasm.query.smart network, addr, msg
    console.log "Response:\n#{YAML.stringify(marshal(result), { indent: 2 })}"
    process.exit 0
  catch err
    await log network, err
    error "Query failed:", err
