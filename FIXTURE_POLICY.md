# Fixture Policy

`ex_vc` ships its interoperability corpus in-repo.

## Contract Levels

- `test/fixtures/upstream/released/` is contractual.
- `test/fixtures/upstream/main/` is advisory drift detection.

Released fixtures are the `ex_vc` parity contract used by tests. Advisory
fixtures exist to show how current upstream branches are changing before those
changes become release targets.

## Runtime Boundary

Using `ex_vc` does not require JavaScript, pnpm, Rust, Cargo, or network
access. Running the normal Elixir test suite should only consume committed
fixtures and local golden cases.

JavaScript tooling is maintainer-only and exists solely to refresh upstream
fixtures under `libs/ex_vc/scripts/upstream_parity/`.

Rust tooling is also maintainer-only and exists solely to refresh `spruceid/ssi`
fixtures under `libs/ex_vc/scripts/ssi_parity/`.

## What Gets Committed

Commit:

- normalized JSON fixtures
- corpus manifests with provenance
- recorder source code
- package manager manifests and lockfiles for recorders

Do not commit:

- scratch captures
- temporary upstream checkouts
- debug dumps
- machine-specific cache files

## Divergence Rules

Add or keep an explicit divergence only when:

1. strict `ex_vc` behavior is already clear,
2. the upstream difference is real and reproducible,
3. the difference is captured in a committed fixture, and
4. the README, `INTEROP_NOTES.md`, and tests explain the exception.

