# Vendored dependencies

Dependencies are ordinary files, not git submodules. No installation is needed
to compile or test after checkout. The upstream files have not been modified.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.4.0) | `v5.4.0` | `ERC20.sol` and its four transitive imports, plus license | MIT |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `v1.9.7` | Complete `src/` tree and both licenses; used only by tests | MIT / Apache-2.0 |

OpenZeppelin files live in `lib/openzeppelin-contracts/`; forge-std files live in
`lib/forge-std/`. `remappings.txt` resolves all imports inside the repository.

Sources were obtained from the upstream release archives:

- `https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.4.0`
  — archive SHA-256: `b89829be48bc501051002191733268a93ef6e238a4bb65d8fd1cbdf3969050d1`
- `https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7`
  — archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`

`lib/SHA256SUMS` records hashes of every included upstream file. Verify them
locally from the repository root with `sha256sum --check lib/SHA256SUMS`.
