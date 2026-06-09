## Why

For pnpm repositories (e.g. `jobber-frontend`), the analyzer uploads a blank `current_version` for essentially every tracked library, so Library Tracking shows no installed version (LIBTRACK-136). The current-version lookup parses `pnpm list --depth=0 --silent` **text** with regexes that require a leading tree prefix (`├── `) before each package name. In the non-interactive CI environment pnpm emits bare `name@version` lines with no prefix, so the regexes match nothing and `current_version` is left empty. A related defect in the same code path makes per-workspace analysis non-functional: `pnpm list --dir <subdir>` resolves to the workspace root, so every workspace is analyzed against identical root-level data.

## What Changes

- Replace the text + regex current-version resolution in `Pnpm#add_all_libraries` with the structured `pnpm list ... --json` output (the repo already consumes `pnpm list --json` for the dependency graph via `run_pnpm_list`). Read each package's `version` field directly instead of scraping rendered tree output.
- Resolve current versions from the correct workspace's `dependencies` and `devDependencies` so per-workspace analysis reflects that workspace, not the repo root.
- Preserve existing downstream behavior: the merge with libyear data (`parse_libyear`), the multi-occurrence version range (`a..b` via `calculate_version`), and the uploaded `libraries[].version` field shape.
- Remove the dependence on terminal/TTY-specific rendering so results are identical in local and CI runs.

## Capabilities

### New Capabilities
- `pnpm-version-analysis`: Resolving the installed ("current") version of each dependency in a pnpm project/workspace and exposing it for upload, using structured pnpm output rather than rendered text.

### Modified Capabilities
<!-- None: no existing specs in this repository. -->

## Impact

- **Code**: `lib/library_version_analysis/pnpm.rb` — `add_all_libraries` (rewritten to parse JSON), and its callers `get_versions` / `get_versions_for_workspace`. Touches how `Versionline#current_version` is populated before `parse_libyear` merges libyear data.
- **Behavior**: `current_version` becomes populated for pnpm repos; the uploaded Library Tracking payload (`server_data`) carries real versions. Per-workspace uploads become genuinely distinct.
- **Tests**: `spec/pnpm_spec.rb` — `add_all_libraries` is currently stubbed; add coverage for JSON-based resolution and workspace scoping.
- **Out of scope (related, separately owned)**: `jobber-frontend`'s `scripts/codeAnalysis/analyzers/libraryVersionAnalysis.ts` greedily `JSON.parse`-ing the gem's stdout and failing on Ruby hash-inspect output (the `static_analysis` CI job error). Tracked as a separate jobber-frontend-owned change.
