import { $ } from 'bun'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  cmd = prog.command 'test'
    .description 'Run your project\'s tests. Currently just an alias for `cargo test`.'
    .action ->
      await $"cargo test"
