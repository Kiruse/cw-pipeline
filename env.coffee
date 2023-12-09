import fs from 'fs/promises'
import path from 'path'

PKG = JSON.parse await fs.readFile path.resolve(import.meta.dir, 'package.json'), 'utf8'
export VERSION = process.env.VERSION = PKG.version
