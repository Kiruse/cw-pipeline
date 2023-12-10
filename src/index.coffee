import { commands } from './cmds/index.coffee'
import { Command } from 'commander'

unless process.env.VERSION
  throw Error 'VERSION environment variable not set.'

program = new Command 'cw-pipeline'
program.version process.env.VERSION

cmd program for cmd in commands

program.parse()
