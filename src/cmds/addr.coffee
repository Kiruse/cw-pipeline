import YAML from 'yaml'
import addresses from '../address-book'

###* @param {import('commander').Command} prog ###
export default (prog) ->
  cmd = prog.command 'addr'
    .description 'Manage your address book.'
  cmd.command 'set <name> <address> [note]'
    .description 'Set an address in your address book.'
    .action (name, address, note) ->
      addresses[name] = { address, note }
      await addresses.$save()
      console.log 'Address saved.'
  cmd.command 'get <name>'
    .description 'Get an address from your address book.'
    .action (name) ->
      if addresses[name]
        console.log addresses[name].address
      else
        console.error 'Address not found.'
        process.exit 1
  cmd.command 'list'
    .description 'List all addresses in your address book.'
    .action ->
      addrs = addresses.$clean()
      if Object.keys(addrs).length > 0
        console.log YAML.stringify addrs, indent: 2
      else
        console.error 'You have no addresses saved.'
        process.exit 1
  cmd.command 'unset <name>'
    .description 'Remove an address from your address book.'
    .action (name) ->
      if addresses[name]
        delete addresses[name]
        await addresses.$save()
        console.log 'Address removed.'
      else
        console.error 'Address not found.'
        process.exit 1
  cmd.command 'note <name> [note]'
    .description 'Get or set a note on an address in your address book.'
    .action (name, note) ->
      unless addresses[name]
        console.error 'Address not found.'
        process.exit 1
      if note
        addresses[name].note = note
        await addresses.$save()
        console.log 'Note saved.'
      else
        if addresses[name].note
          console.log addresses[name].note
        else
          console.error 'No note found.'
          process.exit 1
  cmd.command 'clear-note <name>'
    .description 'Clear the note on an address in your address book.'
    .action (name) ->
      if addresses[name]
        delete addresses[name].note
        await addresses.$save()
        console.log 'Note cleared.'
      else
        console.error 'Address not found.'
        process.exit 1
