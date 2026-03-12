# SSI Parity Recorder

This directory contains maintainer-only tooling for recording VC parity
fixtures from the Rust `spruceid/ssi` stack.

It is not required to use `ex_vc` and is not part of the library runtime.

## Usage

```bash
cargo run -- released
cargo run -- main
```

The recorder writes normalized fixtures under `test/fixtures/upstream/ssi/`.

