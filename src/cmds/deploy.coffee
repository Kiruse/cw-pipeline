import { Project } from '~/project'
import { getDeploymentContract, getNetworkConfig, getSigner, inquire, ContractOption, NetworkOption, MainnetOption } from '~/prompting.js'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'deploy'
    .description 'Deploy your smart contract(s) to the blockchain.'
    .addOption ContractOption()
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (options) ->
      proj = await Project.find()
      contract = await getDeploymentContract proj, options.contract
      console.log "Deploying contract #{contract}..."
      console.error "Not yet implemented!"
      # todo: rest of the implementation
