# Vendored dependencies

These dependencies are included as ordinary files. Builds never fetch them.
Only the listed source/license paths were extracted, with contents unchanged.

| Local path | Upstream release | Included files | License |
| --- | --- | --- | --- |
| `lib/openzeppelin-contracts` | [OpenZeppelin Contracts v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | ERC-20 import closure listed below, plus `LICENSE` | MIT |
| `lib/forge-std` | [forge-std v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | Complete `src/` directory, `LICENSE-MIT`, `LICENSE-APACHE` | MIT or Apache-2.0 |

OpenZeppelin production import closure:

```text
contracts/token/ERC20/ERC20.sol
contracts/token/ERC20/IERC20.sol
contracts/token/ERC20/extensions/IERC20Metadata.sol
contracts/utils/Context.sol
contracts/interfaces/draft-IERC6093.sol
```

The forge-std dependency is used only for tests. No dependency manager, submodule,
generated binary, or external library linking is required.

Source archives and SHA-256 checksums recorded when vendoring:

```text
https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2
18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a

https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94
```

The Solidity compiler is pinned by version in `foundry.toml`. It is provided by
Foundry/the verification toolchain and is deliberately not stored in the project.
