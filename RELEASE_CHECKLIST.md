# Release Checklist

1. Update `CHANGELOG.md` using Keep a Changelog headings such as `## [0.1.0] - 2026-03-11`.
2. Confirm the release contract is still accurate in `README.md`, `SUPPORTED_FEATURES.md`, and `INTEROP_NOTES.md`.
3. Refresh released parity fixtures if the contractual oracle-backed surfaces changed.
4. Run in `libs/ex_vc`:
   - `mix format --check-formatted`
   - `EX_VC_USE_LOCAL_DEPS=1 mix compile --warning-as-errors`
   - `EX_VC_USE_LOCAL_DEPS=1 mix test`
   - `EX_VC_USE_LOCAL_DEPS=1 mix docs`
5. Run targeted downstream checks in `apps/delegate` if the public behavior changed:
   - `mix compile --warning-as-errors`
   - `mix test test/delegate_web/controllers/verification_controller_test.exs test/delegate_web/controllers/oid4vci_credential_controller_test.exs`
6. Confirm the version in `mix.exs` matches the intended release and that the changelog entry exists for that version.
7. Sync `libs/ex_vc` into a clean checkout of `github.com/bawolf/ex_vc` with `scripts/sync_standalone_repo.sh /path/to/ex_vc_repo`.
8. Review the standalone repo diff and run its local checks before pushing.
9. Trigger the standalone repo publish workflow with the same version; it should publish to Hex and create the matching tag and GitHub release automatically.
10. Verify the new release on Hex and GitHub after the workflow completes.
