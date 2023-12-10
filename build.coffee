import CoffeeScriptPlugin from 'bun-coffeescript'
import fs from 'fs/promises'
import path from 'path'
import { rimraf } from 'rimraf'
import YAML from 'yaml'
import { VERSION } from './env.coffee'

BUILDDIR = path.resolve import.meta.dir, 'build'
await rimraf BUILDDIR
await fs.mkdir BUILDDIR, recursive: true

output = await Bun.build
  target: 'bun'
  entrypoints: [
    'src/cw-pipeline.coffee'
  ]
  plugins: [
    CoffeeScriptPlugin()
  ]
  define:
    'process.env.VERSION': JSON.stringify VERSION
  minify: true
  outdir: 'build'
unless output.success
  console.error YAML.stringify output.logs
  process.exit 1

await fs.cp path.resolve(import.meta.dir, 'node_modules/yoga-wasm-web/dist/yoga.wasm'), path.resolve(BUILDDIR, 'yoga.wasm')
