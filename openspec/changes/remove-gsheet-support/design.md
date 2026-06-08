## Context

`CheckVersionStatus` currently supports two output modes selected at runtime by the presence of a `spreadsheet_id`:

- **legacy** (`spreadsheet_id` present): write rows to a Google Sheet via `update_spreadsheet()` / `spreadsheet_data()`, authenticating with a Google service account.
- **lt** (`spreadsheet_id` empty/nil): upload a JSON payload to the Library Tracking server.

Every analysis entrypoint (`go_npm`, `go_gemfile`, `go_pnpm`, `get_version_summary`) threads `spreadsheet_id` and a sheet range through, then branches on `@update_spreadsheet` / `@update_server`. The Google Sheet output is deprecated and superseded by Library Tracking.

## Goals / Non-Goals

**Goals:**
- Make Library Tracking the gem's single upload destination.
- Delete all Google Sheets code, dependencies, and the mode-selection branching.
- Simplify the public surface: `CheckVersionStatus.run()` and the CLI no longer accept `spreadsheet_id`.

**Non-Goals:**
- Changing the Library Tracking payload shape or upload behavior.
- Decommissioning the Google service account, the sheet itself, or untracked local credential scripts.
- Broader refactors beyond what removing the gsheet path requires (e.g. the remaining "ugly legacy hack" result-key mapping is left as-is).

## Decisions

- **Remove the parameter rather than ignore it (BREAKING).** The only known caller is Jobber, which we control and are updating under JOB-171738. A clean signature is preferable to carrying a permanently-ignored argument.
- **Always upload to Library Tracking.** The `@update_spreadsheet` / `@update_server` flags and the `variant` toggle are deleted; `get_version_summary` and `go_pnpm` call `LibraryTracking.upload` unconditionally.
- **Capture surviving behavior as a new spec.** The repo has no existing specs, so rather than writing a "removal delta" against nothing, we record the post-change contract as the `library-version-upload` capability.

## Risks / Trade-offs

- **Cross-repo ordering.** The gem cannot drop `spreadsheet_id` while Jobber still passes it. Mitigation: land the Jobber change (JOB-171738) first so it stops passing the argument, then release this gem change; or release them together. The OpenSpec changes are linked via the Jira "relates to" link.
- **Lost gsheet output.** Anyone still reading the Google Sheet loses updates. Accepted: the sheet is already deprecated and replaced by Library Tracking.
- **Stale env/credentials.** `VERSION_STATUS_SPREADSHEET_ID` and `GOOGLE_*` vars become unused; leaving them set is harmless but should be cleaned up out-of-band.
