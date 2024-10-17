import { commands } from './cmds/index.coffee'
import { Command } from 'commander'
import { VERSION } from '../env.coffee'

program = new Command 'cw-pipeline'
program.version VERSION

cmd program for cmd in commands

program.parse()
