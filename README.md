# cw-pipeline
*CosmWasm Pipeline* is a WIP utility tool for *Cosmos Smart Contract* developers to assist them in their endeavors to build, deploy & maintain a *CosmWasm*-based smart contract.

## Usage
*CW Pipeline* is built on top of [Bun](https://bun.sh/), a JavaScript runtime and an alternative to [Node.js](https://nodejs.org/). With Bun installed, install `cw-pipeline` with `bun add -g https://github.com/Kiruse/cw-pipeline.git`. You should now be able to call `cw-pipeline` anywhere. Refer to `cw-pipeline --help` for more information on each subcommand's usage.

# Roadmap
- [x] Contract instantiation
- [/] DevEnv setup (WIP)
- [/] Project scaffolding (WIP)
- [ ] `schema generate` subcommand. Generate the `src/bin/schema.rs` file based on the contents of the repository. Then generate the TypeScript type declarations from schemas.
- [ ] Generalize for different chains. Currently only built & tested on Terra, though other chains should work, too, but needs testing.
