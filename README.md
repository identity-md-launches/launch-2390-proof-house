# Proof House (PH)

Proof House is a fixed-supply ERC-20 token. The deployable contract is
[`ProofHouse`](src/ProofHouse.sol), which uses the vendored OpenZeppelin ERC-20
implementation without overriding its transfer or approval behavior.

## Token and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity identifier | `ProofHouse` |
| Source / artifact | `src/ProofHouse.sol` / `out/ProofHouse.sol/ProofHouse.json` |
| Name | `Proof House` |
| Symbol | `PH` |
| Decimals | `18` |
| Supply | `1,000,000,000 PH` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Constructor arguments | None; encoded argument bytes are empty |
| Constructor value | `0` ETH (nonpayable) |
| Initial recipient | Immediate constructor caller (`msg.sender`) |
| Intended launch chain | Ethereum, chain ID `1` |

The constructor mints the entire supply exactly once, emitting the ERC-20
`Transfer` event from the zero address. When the factory deploys through CREATE
or CREATE2, the factory receives all tokens. A direct deployment instead gives
all tokens to that direct deployer. No allocation is made to any other address
inside the constructor, and it makes no external calls.

The launch service deploys the compiled creation bytecode with no constructor
arguments. There are no linked libraries, proxies, initialization calls, or
post-deployment configuration requirements. Only `ProofHouse` is a production
contract; contracts under `test/` are local verification helpers.

## Behavior and assumptions

- Transfers deliver the exact requested amount. There are no token transfer
  taxes, fees, burns, rebases, restrictions on trading, or recipient callbacks.
- The supply cannot be minted or burned after deployment. No owner, administrator,
  pause, blacklist, seizure, upgrade, or recovery function exists.
- Standard `transfer`, `approve`, `transferFrom`, `balanceOf`, `allowance`, and
  `totalSupply` functions are available. Successful mutations return `true`;
  invalid operations revert with OpenZeppelin ERC-20 custom errors.
- Zero-amount transfers between nonzero addresses are allowed and emit `Transfer`.
  Self-transfers preserve balances. Transfers to the zero address and approvals
  to the zero address revert.
- Finite allowances decrease on `transferFrom`, including transfers back to the
  same holder. A maximum `uint256` allowance is treated as unlimited and does not
  decrease. Holders can revoke approvals with `approve(spender, 0)`.
- `approve` replaces an existing allowance. Applications should account for the
  standard ERC-20 allowance replacement race: revoke an old allowance and wait
  for confirmation before granting a replacement. Prefer limited approvals.
- `Approval` is emitted on `approve`. This OpenZeppelin implementation does not
  emit `Approval` when `transferFrom` spends an allowance; indexers should read
  `allowance` for its current value. Every token movement emits `Transfer`.
- The token offers no permit, signatures, staking, vesting, or application
  contracts. It accepts no ordinary ETH payments and cannot recover tokens or
  forcibly sent ETH. A transfer to an address without a withdrawal mechanism
  can leave PH inaccessible without changing `totalSupply`.

## Launch responsibilities

The factory and launch service are responsible for distributing the initial
supply and opening the pool. The supplied launch economics are a 10% swarm
allocation, 80% pool allocation, and 10% remainder. These are performed outside
the token, so the constructor always gives the factory the whole supply first.
For this launch, the remainder recipient is
`0xff3e8d9ba776662ca6ed1420ee366afb436d2684`, the pair is IMD at
`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, and the specified initial market
capitalization is `4500000000000000000000` IMD base units. The launch policy's
pool fee is `12500` (1.25%) and tick spacing is `60`. These are launch-service
parameters, not token constructor inputs or configurable token fees. The
service derives the opening price and produces the launch manifest separately.

No production deployment, broadcast, or signing is part of this repository's
tests. The launch operator must use the reviewed `ProofHouse` artifact, verify
the deployed metadata/supply and factory balance before distribution, check
allocation receipts, and arrange source verification and independent review
before release.

### After launch

There are no setters or admin duties. Holders control transfers and approvals;
the deployer has no special rights over their balances. Users are responsible
for recipient correctness and spender authorization. Operators should monitor
the launch distribution and publish the deployed token address and verified
source. Lost funds and compromised approvals cannot be reversed by an admin.

## Build and test

Use Foundry with Solidity `0.8.26` available. The root `foundry.toml` pins that
compiler, targets the Cancun EVM, enables the optimizer with 200 runs, and sets
`bytecode_hash = "none"` for reproducible launch bytecode. All Solidity
dependencies and licenses are ordinary files in `lib/`; no network dependency
installation or git submodules are needed. The compiler itself is supplied by
the toolchain, not vendored here.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x2f988f2d8eaa170a344114c94df8d287e8101599d97c20997074512806ea14ca forge test
forge fmt --check
```

The seed is passed to the runner; test functions do not read or modify the
environment. Tests require no RPC, fork, key, filesystem permission, or FFI.
Every test initializes its own state, including when run in parallel.

- `test/ProofHouse.t.sol` checks metadata, constructor mint/event, exact and full
  transfers, zero/self transfers, approval events/replacement/revocation,
  finite/unlimited allowances, unauthorized spending, zero-address rejection,
  insufficient balance/allowance, rollback of failed transfers, and absence of
  common mint/burn/admin entry points. Four fuzz tests exercise valid and invalid
  amounts and recipients with 1,024 cases each.
- `test/ProofHouseLaunch.t.sol` checks CREATE2 deployment by arbitrary callers
  (1,024 fuzz cases), factory receipt of the full supply, distribution, claims,
  and exact pool-to-trader and trader-to-pool transfers. The latter test checks
  token accounting, not actual Uniswap pool initialization or swaps.
- `test/ProofHouseInvariant.t.sol` checks conservation of supply and balances
  and agreement with an independent allowance model through randomized sequences
  of transfers, approvals, and delegated transfers. Each invariant uses 128 runs
  of 64 calls across four local actors, with unexpected reverts failing the run.

The supplied protected tests were read to check launch expectations. Their full
factory/Uniswap harness and launch environment belong to the independent
verifier and are not present in this project. Local tests do not claim to run
that harness. Test-only actors are not production deployment parameters.

Security review used the supplied reference to examine mint reachability,
authorization, arithmetic, failed-call rollback, and external-call exposure.
The production contract has only its constructor customization and constant;
all public transfer/approval behavior comes from the vendored ERC-20. There are
no oracle, randomness, time, signature, or callback dependencies. Validation
uses Foundry compilation, unit/fuzz/invariant tests, and formatting; Slither and
Mythril were not run. These checks do not replace an independent security audit.

See [DEPENDENCIES.md](DEPENDENCIES.md) for pinned source provenance and licenses.
