# library-version-upload Specification

## Purpose
TBD - created by archiving change remove-gsheet-support. Update Purpose after archive.
## Requirements
### Requirement: Library Tracking is the sole upload destination

The gem SHALL analyze library versions for a repository/source and upload the results only to the Library Tracking server. It SHALL NOT write to Google Sheets.

#### Scenario: npm or gemfile analysis uploads to Library Tracking

- **WHEN** `CheckVersionStatus.run(repository:, source:)` is invoked with source `npm` or `gemfile`
- **THEN** the parsed results are uploaded to Library Tracking via `LibraryTracking.upload`
- **AND** no Google Sheets API call is made

#### Scenario: pnpm analysis uploads each workspace to Library Tracking

- **WHEN** `CheckVersionStatus.run(repository:, source: "pnpm")` is invoked
- **THEN** each discovered workspace's results are uploaded to Library Tracking
- **AND** no Google Sheets API call is made

### Requirement: No Google Sheets parameters or dependencies

The gem's public interface SHALL NOT accept a spreadsheet identifier, and the gem SHALL NOT depend on Google API or Google auth libraries.

#### Scenario: run() rejects a spreadsheet_id argument

- **WHEN** a caller invokes `CheckVersionStatus.run` with a `spreadsheet_id:` keyword
- **THEN** the call fails with an unknown-keyword error (the parameter no longer exists)

#### Scenario: CLI takes only repository and source

- **WHEN** a user runs `analyze <repository> <source> [context]`
- **THEN** the command analyzes and uploads to Library Tracking
- **AND** there is no argument form that targets a Google Sheet

#### Scenario: Google libraries are not loaded

- **WHEN** the gem is required
- **THEN** it does not require `googleauth` or `google/apis/sheets_v4`
- **AND** `googleauth` / `google-api-client` are absent from the gemspec dependencies

