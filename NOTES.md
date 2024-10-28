# Developer Notes
## On the subject of Codegen
While we can probably get away with generating code from the JSON schemas, I frankly think it would grant us much finer control if we generate code akin to the `write_api!` macro from the `cosmwasm-schema` crate.

Generating code from the JSON schemas is generally problematic, as the schemas are actually limited in their descriptiveness, as many of the values are simply encoded to strings. For example, `u64`, `Uint128` and `Uint256` are expressed as strings, so code generated from these schemas would not be able to distinguish between regular strings and stringified numbers. On the other hand, generating code similar to `write_api!` allows us to generate code that can properly serialize & deserialize the original types.
