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
