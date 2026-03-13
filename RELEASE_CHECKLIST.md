# Release Checklist

1. Update `CHANGELOG.md` using Keep a Changelog headings such as `## [0.1.1] - 2026-03-12`.
2. Confirm the release contract is still accurate in `README.md`, `SUPPORTED_FEATURES.md`, and `INTEROP_NOTES.md`.
3. Refresh released parity fixtures if the contractual oracle-backed surfaces changed.
4. Run `scripts/release_preflight.sh`.
5. Run targeted downstream checks in `apps/delegate` if the public behavior changed:
   - `mix compile --warning-as-errors`
   - `mix test test/delegate_web/controllers/verification_controller_test.exs test/delegate_web/controllers/oid4vci_credential_controller_test.exs`
6. Confirm the version in `mix.exs` matches the intended release and that the changelog entry exists for that version.
7. If `mix.exs` depends on a newer `ex_did` release, publish `ex_did` first so the standalone `ex_vc` repo can resolve the Hex dependency.
8. Sync `libs/ex_vc` into a clean checkout of `github.com/bawolf/ex_vc` with `scripts/sync_standalone_repo.sh /path/to/ex_vc_repo`.
9. Verify the mirrored required file set with `scripts/verify_standalone_repo.sh /path/to/ex_vc_repo`.
10. Direct standalone-repo edits are temporary hotfixes only and must be backported to `libs/ex_vc` immediately.
11. Review the standalone repo diff and run `mix ex_vc.release.gate` in the standalone repo before pushing.
12. Trigger the standalone repo publish workflow with the same version; it should publish to Hex and create the matching tag and GitHub release automatically.
13. Verify the new release on Hex and GitHub after the workflow completes.
