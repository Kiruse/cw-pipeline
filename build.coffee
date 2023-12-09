import CoffeeScriptPlugin from 'bun-coffeescript'
import { VERSION } from './env.coffee'

Bun.build
  target: 'bun'
  entrypoints: [
    'src/index.coffee'
  ]
  plugins: [
    CoffeeScriptPlugin()
  ]
  define:
    'process.env.VERSION': JSON.stringify VERSION
  minify: true
  outdir: 'build'
