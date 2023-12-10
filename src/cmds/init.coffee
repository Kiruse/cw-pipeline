###* @param {import('commander').Command} prog ###
export default (prog) ->
  prog.command 'init'
    .description 'Initialize a new CosmWasm project using the cw-template.'
    .action -> error 'not yet implemented'
