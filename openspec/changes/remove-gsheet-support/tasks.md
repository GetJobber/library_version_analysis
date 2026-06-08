## 1. Remove Google Sheets code from CheckVersionStatus

- [x] 1.1 Remove `require "googleauth"` and `require "google/apis/sheets_v4"` from `lib/library_version_analysis/check_version_status.rb`.
- [x] 1.2 Delete the `update_spreadsheet()` and `spreadsheet_data()` methods.
- [x] 1.3 Remove the `spreadsheet_id` mode branch in `go()` (the `@update_spreadsheet` / `@update_server` / `variant` logic); always upload to Library Tracking.
- [x] 1.4 Remove `spreadsheet_id` and the sheet `range` arguments from `go_npm`, `go_gemfile`, `go_pnpm`, and `get_version_summary`; make `LibraryTracking.upload` unconditional.
- [x] 1.5 Remove the hardcoded Sheets range constants and the legacy source-name mapping that only fed `spreadsheet_data`.

## 2. Update public interface (BREAKING)

- [x] 2.1 Remove the `spreadsheet_id:` keyword from `CheckVersionStatus.run()`.
- [x] 2.2 Update `exe/analyze` to take only `<repository> <source> [context]` (drop the spreadsheet_id argument form) and refresh its usage text.
- [x] 2.3 Remove the `VERSION_STATUS_SPREADSHEET_ID` read from `Analyze.go` and pass only `repository`/`source`.

## 3. Dependencies and docs

- [x] 3.1 Remove `googleauth` and `google-api-client` from `library_version_analysis.gemspec`; run `bundle install` and confirm the lockfile updates cleanly.
- [x] 3.2 Update `README.md` to remove the deprecated "Version Status spreadsheet" and Google keys sections.

## 4. Verify

- [x] 4.1 Run `bundle exec rspec` and confirm `CheckVersionStatus` specs pass (note any pre-existing unrelated failures). (CheckVersionStatus 7/7 pass; `bundle install` clean without Google gems. 16 pre-existing `uninitialized constant Open3` failures in npm/pnpm specs are unrelated to this change.)
- [x] 4.2 Grep the repo for `spreadsheet`, `googleauth`, `sheets_v4`, `VERSION_STATUS_SPREADSHEET_ID` and confirm no remaining references in code.
- [x] 4.3 Confirm ordering with JOB-171738: Jobber must stop passing `spreadsheet_id` before (or together with) releasing this change.
