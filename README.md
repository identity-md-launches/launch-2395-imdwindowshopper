# ImdWindowShopper (IWS)

A fixed supply ERC-20 for Ethereum, implemented in
[`src/ImdWindowShopper.sol`](src/ImdWindowShopper.sol) using the vendored
OpenZeppelin Contracts ERC-20. The constructor mints the entire supply once to
its immediate caller (`msg.sender`).

## Token and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract | `ImdWindowShopper` |
| Artifact | `out/ImdWindowShopper.sol/ImdWindowShopper.json` |
| Token name | `ImdWindowShopper` |
| Token symbol | `IWS` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000 IWS` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY` |
| Constructor arguments | None (`[]`) |
| Constructor value | `0` ETH |
| Launch chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |
| EVM target | `cancun` |
| Optimizer | Enabled, `200` runs |
| Metadata bytecode hash | `none` |
| Application contracts / linked libraries | None |

Deploy the compiled creation bytecode directly through the launch factory. Both
CREATE and CREATE2 work without initialization calls or external dependencies.
The factory receives all `10^27` units; a direct deployment instead allocates
them to that direct deployer. No recipient address or owner parameter is needed.
The constructor emits one `Transfer(address(0), deployer, INITIAL_SUPPLY)` event.

The separate launch process supplies the manifest, deployment, liquidity setup
and distribution. Its supplied allocation is 10% to the swarm distributor, 80%
to pool seeding, and 10% to the requester's remainder recipient. The token itself
does not allocate balances to those parties or store any launch addresses.
All recipients receive the full amount of each successful transfer. The launch
process is responsible for the supplied IMD pair, fee, price and other pool
parameters; they are not token configuration.

## Behavior and assumptions

- Metadata and supply are fixed. There is no public mint, burn, owner, pause,
  blacklist, seizure, upgrade, tax, rebase, transfer limit or external callback.
- `transfer`, `approve` and `transferFrom` return `true` on success and revert
  with OpenZeppelin ERC-20 custom errors on invalid inputs. Transfers emit
  `Transfer`, and explicit approvals emit `Approval`.
- Zero-amount transfers and self-transfers are supported. Sending to the zero
  address and approving a zero spender revert. A self-transfer still requires
  a sufficient balance; `transferFrom` still requires the caller's allowance.
- Finite allowances decrease when spent. `type(uint256).max` denotes an
  unlimited allowance and is not reduced. Spending an allowance does not emit
  an additional `Approval` event in this OpenZeppelin version.
- Replacing an allowance uses normal ERC-20 semantics. Holders should revoke
  an existing allowance to zero before setting a replacement, accounting for
  transactions that may spend the old allowance before revocation confirms.
- Failed operations revert atomically, including any tentative allowance
  decrement. There is no external contract call in token operations.
- The token has no payable receiver or recovery function. Normal ETH sends
  revert; assets mistakenly sent to the token address cannot be recovered.

## Build and checks

With Foundry and Solidity `0.8.26` installed, run from this repository's root:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xbf0ca2dc55a5e7639ac7f1b0be8b2c5355df727b8f9d4d8b73bd02b2e5eb9cf4 forge test
forge fmt --check
```

The same fuzz seed is pinned in `foundry.toml`, so plain `forge test` also uses
it. Each fuzz test runs 1,024 cases. Stateful invariants run 256 sequences of
64 actions each with unexpected reverts treated as failures. All dependencies
are ordinary source files in `lib/`; builds need no dependency downloads,
submodules, RPC access, FFI, filesystem cheatcode permissions or environment
configuration. Tests neither read nor set environment variables.

Unit and fuzz tests check metadata, exact supply, the single mint event,
CREATE2 factory ownership of the initial balance, exact transfers, approval
replacement and revocation, finite and infinite allowances, zero amounts,
self-transfers, invalid addresses, insufficient balances and allowances,
atomic failure, and rejection of administrative or minting calls. Stateful
tests compare balances and allowances with independent accounting after
arbitrary sequences of transfers, approvals, revocations and delegated spends.

The local launch test checks exact factory distribution, claims and transfers
into and out of a simulated pool address. It does not execute a Uniswap swap.
The supplied protected checks additionally depend on the network's launch
harness, Uniswap v4 contracts and manifest-derived inputs; that integration is
run by the independent verifier and is not reproduced by the local tests.

## After launch

There are no settings to initialize, owner actions or periodic maintenance.
The launch operator must verify the deployed source and compiler settings,
metadata, total supply, initial mint event, distribution and pool integration.
Holders manage their own transfers and allowances; neither the deployer nor
IMD can mint more tokens, freeze balances or reverse transfers. Integrators
must use 18-decimal base units and handle ERC-20 reverts.

Local validation uses Foundry unit tests, fuzzing, stateful invariants and a
manual review against the supplied security checklist. Slither and Mythril
were not run. Independent adversarial review and the launch integration checks
remain the launch process's responsibilities; these local checks are not a
security audit. This project contains no deployment credentials and performs
no broadcast transactions.

Dependency versions, source locations and integrity hashes are recorded in
[`DEPENDENCIES.md`](DEPENDENCIES.md).
