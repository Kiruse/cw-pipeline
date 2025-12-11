import { multipleOf } from 'valibot'
import { CosmWasm } from '@apophis-sdk/cosmwasm'
import fs from 'fs/promises'
import { select } from 'inquirer-select-pro'
import YAML from 'yaml'
import { Project, marshal } from '~/project'
import { getNetworkConfig, getSigner, NetworkOption, MainnetOption, FundsOption, parseFunds, isAddress, inquireEditor, inquire } from '~/prompting.js'
import { isFile } from '~/templating'
import { error, log } from '~/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'exec'
    .description 'Execute a Smart Contract on the blockchain.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .addOption FundsOption()
    .option '-m, --msg <path_or_name>', 'In a project, this may be the name of the message to execute as found in your .cwp/msgs.yml file. Otherwise, it is the path to the YAML file containing your message.'
    .option '--no-validate', 'Whether to skip message validation. Defaults to validating.'
    .argument '[contract]', 'Contract name (if in a project) or address to execute. When omitted, prompts for a contract.'
    .argument '[address]', 'Contract address to execute. When specified, the given contract is assumed to be of the indicated type.'
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
          message: 'Choose a contract to execute'
          options: (input) ->
            contracts
              .filter (c) -> not input.trim() or c.includes(input.trim())
              .sort()
              .map (c) -> { name: c.name, value: c.name }
          multiple: false
      await execAddress { opts..., contract, address, proj, network }

execAddress = ({ proj, network, address, contract, opts... }) ->
  signer = await getSigner()
  await signer.connect [network]

  tmp = await proj.getDeployedContract(network, contract)
  {contract, name: contractName} = tmp
  address ?= tmp.address

  unless opts.msg
    msgs = await proj.getMsgs contract, 'execute'
    error "No execute messages found for #{contract} in .cwp/msgs.yml" unless msgs
    opts.msg = await inquire select,
      name: 'msg.exec'
      message: 'Choose a prepared execute message'
      options: (input) ->
        msgs
          .filter (m) -> not input.trim() or m.includes(input.trim())
          .sort()
          .map (m) -> { name: m, value: m }
      multiple: false
  {msg, funds} = await proj.getMsg({ network, signer }, contract, "execute:#{opts.msg}")
  await proj.validateMsg contract, 'execute', msg if proj and opts.validate

  funds = parseFunds opts.funds ? funds ? []

  report = {
    name: contractName
    contract
    address
    msg
    funds: funds.map((f) -> "#{f.amount}#{f.denom}").join(', ')
  }
  console.log YAML.stringify marshal(report), { indent: 2 }
  error 'User aborted execution' unless await confirm 'Continue?'

  try
    result = await CosmWasm.execute network, signer, address, msg, funds
    await log network, result
    console.log 'Success! Details have been logged to cw-pipeline.log.'
    process.exit 0
  catch err
    await log network, err
    error "Failed to execute contract:", err
