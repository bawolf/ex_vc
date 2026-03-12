# ex_vc

[![Hex.pm](https://img.shields.io/hexpm/v/ex_vc.svg)](https://hex.pm/packages/ex_vc)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/ex_vc)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/bawolf/ex_vc/blob/main/LICENSE)

`ex_vc` is a focused Verifiable Credentials 2.0 library for Elixir.

Quick links: [Hex package](https://hex.pm/packages/ex_vc) | [Hex docs](https://hexdocs.pm/ex_vc) | [Supported features](https://github.com/bawolf/ex_vc/blob/main/SUPPORTED_FEATURES.md) | [Interop notes](https://github.com/bawolf/ex_vc/blob/main/INTEROP_NOTES.md) | [Fixture policy](https://github.com/bawolf/ex_vc/blob/main/FIXTURE_POLICY.md)

Release 1 is intentionally narrow:

- VC 2.0 credential normalization and validation
- Verifiable Presentation loading plus structural verification boundaries
- normalized issuance helpers
- `vc+jwt` issuance and verification
- DID-based verification key resolution through `ex_did`

Data Integrity and SD-JWT VC code remains in-tree for later parity work, but they
are not part of the release 1 support contract, Hex support posture, or parity
claims.

## Status

Release 1 supported surface:

- `ExVc.load/1`, `ExVc.to_map/1`
- `ExVc.validate/2`, `ExVc.valid?/2`
- `ExVc.issue/2`
- `ExVc.verify/2`
- `ExVc.verify_presentation/2`
- `ExVc.sign_jwt_vc/3`, `ExVc.verify_jwt_vc/2`
- DID-based verification through `ex_did`, including method-specific key
  normalization such as `did:jwk` and multikey-backed `did:key`

Runtime deliberately does not require:

- Node / pnpm
- Rust / Cargo
- network access

Those toolchains are maintainer-only and reserved for refreshing parity fixtures.

## Installation

```elixir
def deps do
  [
    {:ex_vc, "~> 0.1.0"}
  ]
end
```

## Usage

### Validate a VC envelope

```elixir
credential = %{
  "@context" => ["https://www.w3.org/ns/credentials/v2"],
  "type" => ["VerifiableCredential"],
  "issuer" => "did:web:example.com",
  "credentialSubject" => %{"id" => "did:key:z6MkwExample"}
}

{:ok, report} = ExVc.validate(credential)
report.parsed.normalized
```

### Issue a normalized credential

```elixir
{:ok, credential} =
  ExVc.issue(
    %{"credentialSubject" => %{"id" => "did:key:z6MkwExample"}},
    issuer: "did:web:example.com",
    types: ["VerifiableCredential", "ExampleCredential"]
  )
```

### Sign and verify VC-JWT

```elixir
{:ok, jwt} = ExVc.sign_jwt_vc(credential, issuer_jwk, alg: "ES256")
{:ok, verification} = ExVc.verify_jwt_vc(jwt, jwk: issuer_public_jwk)

verification.format
verification.credential
```

You can also verify through DID resolution instead of passing a raw JWK:

```elixir
{:ok, verification} = ExVc.verify_jwt_vc(jwt, issuer_did: "did:key:zDna...")
```

### Use auto-detected verification

```elixir
{:ok, verification} = ExVc.verify(jwt, issuer_did: "did:key:zDna...")
verification.verified
```

### Validate a Verifiable Presentation

```elixir
presentation = %{
  "@context" => ["https://www.w3.org/ns/credentials/v2"],
  "type" => ["VerifiablePresentation"],
  "holder" => "did:key:z6MkwHolder",
  "verifiableCredential" => [credential]
}

{:ok, result} = ExVc.verify_presentation(presentation)
result.verified
```

`verify_presentation/2` in release 1 is a strict VP boundary:

- validates the VP envelope
- validates embedded credential envelope shape
- fails closed if embedded credential verification is requested and fails

It is not advertised as full proof-bearing VP interoperability yet.

## Validation Model

`ExVc.validate/2` enforces the generic VC envelope:

- VC 2.0 context presence
- `VerifiableCredential` type presence
- issuer presence as string or issuer object
- `credentialSubject` presence as object or list of objects
- ISO8601 validation for `validFrom`, `validUntil`, and `proof.created`
- temporal ordering for `validFrom` / `validUntil`
- generic status object validation plus Bitstring Status List entry fields when that type is used

Application or profile semantics belong in caller-supplied validators.

## Interoperability Strategy

`ex_vc` uses three evidence layers:

- property tests for invariants
- golden fixtures for deterministic library behavior
- committed released fixtures for oracle-backed surfaces

The parity fixture layout mirrors `ex_did`:

- `test/fixtures/upstream/dcb/released/`
- `test/fixtures/upstream/dcb/main/`
- `test/fixtures/upstream/ssi/released/`
- `test/fixtures/upstream/ssi/main/`

Release 1 parity claims are intentionally narrow:

- VC envelope validation is backed by committed DCB and Spruce fixtures
- `vc+jwt` and VP boundary behavior are covered by local runtime tests
- Data Integrity and SD-JWT VC are deferred from the public parity contract

See:

- `SUPPORTED_FEATURES.md`
- `INTEROP_NOTES.md`
- `FIXTURE_POLICY.md`

## Open Source Notes

- License: MIT
- Changelog: `CHANGELOG.md`
- Fixture policy: `FIXTURE_POLICY.md`
- Canonical package repository: [github.com/bawolf/ex_vc](https://github.com/bawolf/ex_vc)
- The stable public facade for release 1 is `ExVc`; deferred proof adapters may
  exist in-tree without being part of the support contract

## Maintainer Workflow

`ex_vc` currently lives in the `delegate` monorepo and is mirrored into the
standalone `ex_vc` repository for publishing and external consumption.

The intended workflow is:

1. make library changes in `libs/ex_vc`
2. run `mix release.gate`
3. sync the package into a clean checkout of `github.com/bawolf/ex_vc`
4. review and push from the standalone repo
5. trigger the publish workflow from the standalone repo

A helper script for the sync step lives at `scripts/sync_standalone_repo.sh`.

The standalone repository should carry GitHub Actions workflows for:

- CI on push and pull request
- manual publish through `workflow_dispatch`

The publish workflow expects a `HEX_API_KEY` repository secret in the standalone
`ex_vc` repository. Once triggered, it publishes to Hex and then creates the
matching Git tag and GitHub release automatically.

## Maintainer Tooling

Refresh TypeScript parity fixtures:

```bash
cd libs/ex_vc/scripts/upstream_parity
pnpm install
pnpm run record:released
pnpm run record:main
```

Refresh Rust parity fixtures:

```bash
cd libs/ex_vc/scripts/ssi_parity
cargo run -- released
cargo run -- main
```

Normal users and release consumers do not need either toolchain.

## Release Automation

The standalone `ex_vc` repository is expected to carry:

- CI on push and pull request
- a manual publish workflow

The publish workflow should be triggered through `workflow_dispatch` after the
version and changelog are ready. It publishes to Hex first and then creates the
matching Git tag and GitHub release automatically. It expects a `HEX_API_KEY`
repository secret in the standalone `ex_vc` repository.

Run the local release gate with:

```bash
mix release.gate
```
