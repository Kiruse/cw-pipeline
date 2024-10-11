import { getNetworkConfig, getSigner, NetworkOption, MainnetOption } from '~/prompting.js'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'whoami'
    .description 'Print the current wallet address.'
    .addOption NetworkOption()
    .addOption MainnetOption()
    .action (options) ->
      network = await getNetworkConfig options
      signer = await getSigner()
      await signer.connect [network]
      console.log signer.address network
      process.exit 0
