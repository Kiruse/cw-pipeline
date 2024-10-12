# cw-pipeline
*CosmWasm Pipeline* is a WIP utility tool for *Cosmos Smart Contract* developers to assist them in their endeavors to build, deploy & maintain a *CosmWasm*-based smart contract.

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
- [x] Project scaffolding
- [ ] Multi-chain support (Chain Registry) (WIP)
- [ ] Multi-chain support (Custom)
- [ ] DevEnv setup (WIP)
- [ ] Generate schemas as part of the production build process.
- [ ] Secret storage.
