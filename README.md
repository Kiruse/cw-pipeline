# cw-pipeline
*CosmWasm Pipeline* is a WIP utility tool for *Cosmos Smart Contract* developers to assist them in their endeavors to build, deploy & maintain a *CosmWasm*-based smart contract.

Currently, *CW Pipeline* requires [Bun](https://bun.sh/), but eventually, I aim to release it via `npm` & Vanilla `node`.

# Usage
*CW Pipeline* is built on top of [Bun](https://bun.sh/), a JavaScript runtime and an alternative to [Node.js](https://nodejs.org/). With Bun installed, install `cw-pipeline` with `bun add -g https://github.com/Kiruse/cw-pipeline.git`. You should now be able to call `cw-pipeline` anywhere. Refer to `cw-pipeline --help` for more information on each subcommand's usage.

## Configuration
There are two configuration files used by *CW Pipeline*:
- `~/.cw-pipeline/config.yml` is used to store your user-specific settings.
- `cwp.yml` is used to store project-specific settings. These override the user-specific ones.

The configuration format is still a work in progress, but currently follows the following pattern:
```yaml
<network-name>:
  endpoints?:
    rest?: <rest-endpoint>
    rpc?: <rpc-endpoint>
    ws?: <websocket-endpoint>
```

Where a `?` indicates that the option is optional.

## Environment Variables
Various commands can substitute options with environment variables. These commands make it easier to use *CW Pipeline* in automated environments, such as in a CI/CD pipeline. The following variables are supported:

- `CWP_NETWORK`: Name of the network to use, as registered in the [Chain Registry](https://github.com/cosmos/chain-registry).
- `CWP_MAINNET`: Set to `true` to use the mainnet instead of the testnet.
- `CWP_MNEMONIC`: Mnemonic to use for signing transactions.
- `CWP_PRIVATE_KEY`: Private key to use for signing transactions.

Note that, currently, the `CWP_MNEMONIC` and `CWP_PRIVATE_KEY` variables are the only way to define your signer. For the sake of operational security, I strongly recommend supplying either of these values just-in-time, e.g. through a CI/CD secret manager or an encrypted-at-rest keyring. Never store credentials in unencrypted project files such as a `.env` file.

# Roadmap
- [x] Contract instantiation
- [x] Project scaffolding (single contract)
- [x] Project scaffolding (monorepo)
- [x] Multi-chain support (Chain Registry)
- [x] Multi-chain support (Custom)
- [ ] DevEnv setup (WIP)
- [x] Generate schemas as part of the production build process.
- [ ] Secret storage.
- [ ] Build with chain-specific features (e.g. standard *TokenFactory* vs. Injective *TokenFactory*)
- [ ] Smart Contract query & execution TS codegen.
- [ ] Unit testing with [cw-orchestrator](https://orchestrator.abstract.money/) and/or [cw-simulate](https://github.com/cosmology-tech/cw-simulate).

# Commands
CW-Pipeline uses a CLI library with built-in introspection, so you can always call `cw-pipeline <command> --help` to get more information about each command; which subcommands, arguments & options it has; and a short description of what it does.

We distinguish between two families of commands: Development and Inspection commands. Development commands assist you in the development of CosmWasm smart contracts. Inspection commands help you inspect the state of the decentralized world.

## Development Commands
- `setup`: Set up your development environment. This currently only supports some limited setup and cannot install missing binary dependencies.
- `init`: Initialize a new project. This will eventually be deprecated in favor of `new project`.
- `new <thing>`: Create a new `thing`. Which things are exactly available depends on the execution context. In a monorepo, for example, you can create `new contract` or `new package`.
- `build [dev|prod]`: Build the project. `build dev` is useful for just testing whether your project builds, or for running local tests. `build prod` will build the project ready for deployment to testnet or to mainnet.
- `store`: Store the compiled artifact. In a single-contract project, it stores the only `artifacts/*.wasm` file it can find. In a monorepo, you must specify which contract to store.
- `instantiate`: Instantiate the last stored contract code. Functions similar to `store`.
- `exec`: Perform a contract execution on the last instantiated contract. If a `msg.exec.yml` file exists, it will be used as the execution message. Otherwise, CWP will open an editor for you to write one, and prepopulate it with the last used message. The editor can be specified with the `EDITOR` environment variable on Linux/macOS.
- `query`: Perform a contract query on the last instantiated contract. Behaves like `exec`.

## Inspection Commands
The decentralized world is massive. These commands are designed to help you navigate it. Most specialized commands are added as subcommands where appropriate.

- `show`: Show information about things, such as network information from the chain registry, transaction information, or CW2-standard contract information.
- `state`: Query the state of a CosmWasm smart contract. The `state show` command comes with some built-in support for common state types, such as JSON, YAML, and BigInt.
- `whoami`: Given proper signer setup, this will print out your signer's address.
- `addr`: Your personal address book. Great when combined with other unix CLI tools like `grep` or `yq`. It is really just a simple key/value store.

### `show` Subcommands
`show` gathers and displays current information about various things of the decentralized world. Unfortunately, it cannot access historical information for lack of an always-on indexer.

- `network`: Show information about a network.
- `tx`: Show information about a transaction.
- `cw2`: Show CW2-standard contract information, if available.
- `project`: Various sub-sub-commands to show information around the current project. A project is detected by searching for a `Cargo.toml` in the current directory's ancestry.
- `drand`: Show information about the DRAND randomness beacon. For example, a network's metadata or the latest round.

# Message Templating
When running the `instantiate`, `migrate`, `execute`, or `query` commands, you require a message specific to your smart contract. Often, you have a schema, but if you don't, you can pass the `--no-validate` flag to skip validation.

You can define messages for your smart contracts in the `.cwp/msgs.yml` file relative to project root. These messages take placeholders which *cwp* will substitute. There are two kinds of placeholders: variables and function invocations.

## Variables
**Variables** take this form: `$(variable_name:type)`. When omitted, `type` is `string`, which should cover most generic cases. However, specifying a `type` allows *cwp* to prompt more directly and apply validations. The following types currently exist:

- `addr`: Prompt the user for an address. Validated for the current network.
- Many more types are in the works.

## Functions
**Function calls* take this form: `$fn_name(arg1, arg2, ...)`. Function calls can be nested, e.g. `$bin($json($tpl(my_template)))` will reference the template `my_template`, convert it to a JSON string, and finally convert it to a base64 string before filling it into the original message. The following functions currently exist:

- `$bin(content)`: Converts its contents to base64.
- `$signer()`: Inserts the current signer's address.
- `$json(content)`: Converts its contents to a JSON string.
- `$tpl(name)`: Evaluates & inserts the named template.

## Templates
The `$tpl(...)` function allows reusing message components. Templates can be defined either as part of a specific message directly or as part of the entire contract. When template names clash, the local one takes precedence.

Templates are evaluated exactly like messages. Templates are recursive, meaning you can reference templates within templates.

**Example:**

```yml
autobond:
  execute:
  - name: Process Queue
    msg:
      process:
        payload: $bin($json($tpl(payload_primary)))
    tpl:
      payload_primary:
        primary: {}
```

This will convert `primary: {}` into a base64-encoded JSON string such that the resulting message is:

```json
{"process":{"payload":"eyJwcmltYXJ5Ijp7fX0="}}
```
