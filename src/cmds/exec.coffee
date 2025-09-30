import { multipleOf } from 'valibot'
import { CosmWasm } from '@apophis-sdk/cosmwasm'
import fs from 'fs/promises'
import { select } from 'inquirer-select-pro'
import YAML from 'yaml'
import { Project, marshal } from '~/project'
import { getNetworkConfig, getSigner, NetworkOption, MainnetOption, FundsOption, parseFunds, isAddress, inquireEditor, inquire } from '~/prompting'
import { isFile } from '~/templating'
import { error, log } from '~/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'exec'
    .description 'Execute a Smart Contract on the blockchain.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .addOption FundsOption()
    .option '-c, --contract <contract>', 'In a project, this may be the name of a deployed contract. Otherwise, it is the contract\'s address.'
    .option '-m, --msg <path_or_name>', 'In a project, this may be the name of the message to execute as found in your .cwp/msgs.yml file. Otherwise, it is the path to the YAML file containing your message.'
    .option '--no-validate', 'Whether to skip message validation. Defaults to validating.'
    .action (opts) ->
      network = await getNetworkConfig opts
      proj = await Project.find().catch(=>)

      # if an address, regardless of monorepo
      if isAddress opts.contract
        error 'Msg must be a filepath when executing on a contract address' unless await isFile opts.msg
        return await execAddress { opts..., proj, network }
      error 'Must specify a contract address when not in a project' unless proj

      unless opts.contract
        contracts = await proj.getDeployedContracts(network)
        opts.contract = await inquire select,
          name: 'contract'
          message: 'Choose a contract to execute'
          options: (input) ->
            contracts
              .filter (c) -> not input.trim() or c.includes(input.trim())
              .sort()
              .map (c) -> { name: c.name, value: c.name }
          multiple: false
      await execAddress { opts..., proj, network }

execAddress = ({ proj, network, contract, opts... }) ->
  signer = await getSigner()
  await signer.connect [network]

  isContractFile = await isFile contract
  contractName = contract
  {msg, funds, addr} = if isContractFile
    msg: await fs.readFile opts.msg, 'utf8'
    addr: contract
    funds: []
  else
    {address: addr, contract, name: contractName} = await proj.getDeployedContract(network, contract)
    unless opts.msg
      msgs = await proj.getMsgs contract, 'execute'
      opts.msg = await inquire select,
        name: 'msg.exec'
        message: 'Choose a prepared execute message'
        options: (input) ->
          msgs
            .filter (m) -> not input.trim() or m.includes(input.trim())
            .sort()
            .map (m) -> { name: m, value: m }
        multiple: false
    data = await proj.getMsg(network, contract, "execute:#{opts.msg}")
    { data..., addr }
  await proj.validateMsg contract, 'execute', msg if proj and opts.validate

  funds = parseFunds opts.funds ? funds ? []

  if addr is contractName
    console.log "Contract at #{contractName}"
  else
    console.log "Contract #{contractName} (#{contract}) at #{addr}"
  console.log "Message:\n#{YAML.stringify marshal(msg), { indent: 2 }}"
  error 'User aborted execution' unless await confirm 'Continue?'

  try
    result = await CosmWasm.execute network, signer, addr, msg, funds
    await log network, result
    console.log 'Success! Details have been logged to cw-pipeline.log.'
    process.exit 0
  catch err
    await log network, err
    error "Failed to execute contract:", err
