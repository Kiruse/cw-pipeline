###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'setup'
    .description 'Setup your CosmWasm Smart Contract development environment.'
    .action -> error 'not yet implemented'
