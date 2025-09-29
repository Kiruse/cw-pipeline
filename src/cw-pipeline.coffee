import { DefaultCosmWasmMiddlewares } from '@apophis-sdk/cosmwasm'
import { Apophis } from '@apophis-sdk/core'
import { commands } from './cmds/index.coffee'
import { Command } from 'commander'
import { VERSION } from '../env.coffee'

program = new Command 'cw-pipeline'
program.version VERSION

Apophis.use DefaultCosmWasmMiddlewares...
await Apophis.init()

await Promise.all commands.map (cmd) -> cmd program

program.parse()

process.on 'unhandledRejection', (reason) ->
  if typeof reason is 'string'
    console.error reason
    process.exit 1
  else
    throw reason
