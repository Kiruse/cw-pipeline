import { File } from 'buffer'
import fs from 'fs/promises'
import Mime from 'mime'
import path from 'path'
import YAML from 'yaml'

import ConfirmMsgSubProgram from 'src/blessed/ConfirmMsgSubProgram'
import { runSubProgram } from 'src/subprogram'
import { error } from 'src/utils'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  cmd = prog.command 'mint'
  mintCw20 cmd
  mintCw721 cmd
  mintNative cmd
  cmd

###* @param {import('commander').Command} prog ###
mintCw20 = (prog) ->
  prog.command 'cw20'
    .action -> error 'not yet implemented'

###* @param {import('commander').Command} prog ###
mintCw721 = (prog) ->
  prog.command('cw721')
    .argument '<metadata_filepath>', 'Local path to a YAML or JSON file describing this NFT\'s metadata (name + description), including OpenSea attributes'
    .argument '<image_filepath>', 'Local path to the NFT\'s image'
    .action (meta, img, options) ->
      if meta.endsWith '.json'
        meta = JSON.parse await fs.readFile(meta, 'utf8')
      else if meta.endsWith '.yaml'
        meta = YAML.parse await fs.readFile(meta, 'utf8')
      else
        error 'metadata_filepath must be a JSON or YAML file'
      validateCw721Metadata meta

      mime = Mime.getType img
      error 'Failed to determine image mime type' unless mime

      imgContent = await fs.readFile img
      img = new File [imgContent], path.basename(img), type: mime

      unless await runSubProgram new ConfirmMsgSubProgram meta
        error 'Aborted. Metadata not confirmed'
      error 'not yet implemented'

###* @param {import('commander').Command} prog ###
mintNative = (prog) ->
  prog.command 'native'
    .action -> error 'not yet implemented'

validateCw721Metadata = (meta) ->
  error 'Invalid metadata' unless meta
  error 'Missing name' unless typeof meta.name is 'string'
  error 'Missing description' unless typeof meta.description is 'string'
  if meta.attributes
    error 'Invalid attributes' unless Array.isArray meta.attributes
    for attr in meta.attributes
      error 'Invalid attribute' unless attr
      error 'Missing attribute trait_type' unless typeof attr.trait_type is 'string'
      error 'Missing attribute value' unless typeof attr.value in ['string', 'number']
