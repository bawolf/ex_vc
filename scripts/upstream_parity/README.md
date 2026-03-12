# Upstream Parity Recorder

This maintainer-only tool records `ex_vc` parity fixtures from current
TypeScript VC libraries into committed fixtures under `test/fixtures/upstream/`.

## Usage

Install the pinned recorder dependencies:

```bash
pnpm install
```

Refresh the required released corpus:

```bash
pnpm run record:released
```

Refresh the advisory upstream-`main` corpus:

```bash
pnpm run record:main
```

Normal `mix test` and normal `ex_vc` usage do not require Node, pnpm, or
network access.

