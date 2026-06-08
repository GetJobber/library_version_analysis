## Why

The gem used to populate a Google Sheet ("gsheet"), but that output has been replaced by the Library Tracking app. The gsheet path is already marked deprecated in the README and is now dead weight: it carries Google API dependencies, service-account auth, and a dual-mode branch that complicates every upload path. (Jira: LIBTRACK-134.)

## What Changes

- Remove the `googleauth` and `google-api-client` gem dependencies.
- Remove the `require "googleauth"` / `require "google/apis/sheets_v4"` imports.
- Remove the `update_spreadsheet()` and `spreadsheet_data()` methods (Google Sheets API client + cell/formula formatting).
- Remove the `spreadsheet_id`-based branch in `go()` (the `@update_spreadsheet` vs `@update_server` mode toggle); the gem always uploads to Library Tracking.
- Remove the hardcoded Google Sheets range constants and the legacy source-name mapping that only fed the spreadsheet.
- **BREAKING**: Remove the `spreadsheet_id` keyword parameter from `CheckVersionStatus.run()` and the corresponding argument handling in the `exe/analyze` CLI.
- Remove the `VERSION_STATUS_SPREADSHEET_ID` read from `Analyze.go`.
- Update `README.md` to drop the deprecated "Version Status spreadsheet" / Google keys sections.

## Capabilities

### New Capabilities
- `library-version-upload`: Describes the gem's surviving output contract — analyzing library versions and uploading results to the Library Tracking server as the single destination.

### Modified Capabilities
<!-- None. The repository has no existing specs; the surviving behavior is captured as a new capability above. -->

## Impact

- **Code**: `lib/library_version_analysis/check_version_status.rb`, `lib/library_version_analysis/analyze.rb`, `exe/analyze`.
- **Dependencies**: drops `googleauth`, `google-api-client`.
- **Config/env**: `VERSION_STATUS_SPREADSHEET_ID` and the `GOOGLE_*` service-account vars are no longer read by the gem.
- **Docs**: `README.md`.
- **Downstream**: Jobber calls `CheckVersionStatus.run(spreadsheet_id:)`. The breaking signature change is coordinated via JOB-171738 (relates to this change). The gem cannot drop the parameter while Jobber still passes it — see ordering note in design.
- **Out of scope**: decommissioning the Google service account / sheet and the untracked local credential scripts (`version_prod.sh`, etc.).
