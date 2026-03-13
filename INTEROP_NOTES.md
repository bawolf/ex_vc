# Interop Notes

`ex_vc` tracks these reference ecosystems:

- Rust: `spruceid/ssi`
- TypeScript: the Digital Bazaar / Digital Credentials VC stack

## Release 1 Contract

Release 1 intentionally narrows its public interoperability claims to:

- VC 2.0 envelope validation
- `vc+jwt` issuance and verification in the Elixir runtime
- Verifiable Presentation structural validation plus embedded credential
  verification boundaries
- DID-based verification key resolution through `ex_did`

Release 1 does not claim public parity for Data Integrity or SD-JWT VC.

## Current Evidence

- VC envelope validation is implemented natively in Elixir and backed by
  committed released fixtures from both reference stacks.
- `vc+jwt` signing and verification are covered by local runtime tests,
  including DID-resolved verification through `ex_did`.
- VP handling is intentionally narrow: structural validation and strict embedded
  credential verification behavior are covered locally, but proof-bearing VP
  interoperability is not claimed.
- Data Integrity and SD-JWT VC remain in-tree as deferred workstreams, not as
  release 1 support claims.

## Deferred Surfaces

These remain out of the release 1 public contract until they have explicit
upstream-recorded parity evidence:

- Data Integrity proof verification and issuance
- SD-JWT VC disclosure and key-binding interoperability
- broader proof-bearing VP interoperability

## Decision Log

Released VC envelope validation currently has no documented DCB-vs-Spruce
divergences. The released divergence manifest lives at
`test/fixtures/divergences/released.json` and must stay empty until a real
cross-oracle disagreement is introduced and explicitly decided.

## Policy

- Do not claim released parity for a surface unless it has committed DCB and/or
  Spruce released fixtures that exercise that exact behavior.
- Every released DCB-vs-Spruce disagreement must have a committed divergence
  entry and a documented winning contract.
- If Rust and TypeScript references diverge, `ex_vc` chooses one explicit
  behavior, records the divergence in fixtures, and documents it here.
- Advisory `main` fixtures are for drift detection only.
