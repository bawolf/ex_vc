# Changelog

All notable changes to `ex_vc` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project intends to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-03-11

### Added
- VC 2.0 credential normalization and validation.
- Verifiable Presentation loading plus structural verification boundaries.
- `vc+jwt` issuance and verification.
- DID-based verification key resolution through `ex_did`.
- Hex-ready package metadata, docs, CI, publish workflow, and standalone sync tooling.

### Changed
- Narrowed the public release 1 contract to VC core, VP boundary behavior, and
  `vc+jwt`.

### Deferred
- Data Integrity and SD-JWT VC remain in-tree for later parity work, but are
  excluded from the public release 1 support contract.
