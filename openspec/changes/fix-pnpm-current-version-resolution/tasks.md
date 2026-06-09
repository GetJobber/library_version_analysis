## 1. Confirm JSON shape

- [x] 1.1 Capture real `pnpm list --depth=0 --json` for `jobber-frontend` root and for one app workspace (e.g. `apps/jobber-online`); record the array/object structure and the `dependencies`/`devDependencies` `version` field shape
- [x] 1.2 Note how `link:`/`workspace:` deps and multi-version packages appear in the JSON, to confirm empty-version and range handling

## 2. Rewrite current-version resolution

- [x] 2.1 Replace the text+regex parsing in `Pnpm#add_all_libraries` with JSON parsing of `pnpm list ... --json` (reuse `run_pnpm_list`), reading each package's `version` from `dependencies` and `devDependencies`
- [x] 2.2 Select the JSON entry matching the analyzed `workspace_path` (by resolved path/name) instead of relying on `--dir`; when no entry matches, log and skip rather than silently falling back to root
- [x] 2.3 Build the `{ name => Versionline }` map with `new_version_line`, combining duplicate names via `calculate_version` to preserve the `a..b` range form
- [x] 2.4 Resolve non-semver specifiers (`link:`, `workspace:`) to an empty current version without aborting the rest of the analysis
- [x] 2.5 Confirm `get_versions` (single-package repo) and `get_versions_for_workspace` (monorepo) both route through the new resolution and still feed `parse_libyear` unchanged

## 3. Tests

- [x] 3.1 Add a dedicated `#add_all_libraries` context in `spec/pnpm_spec.rb` (the method was stubbed everywhere) with fixtures based on the real JSON from task 1
- [x] 3.2 Cover: scoped + unscoped names resolve; per-workspace results differ; multi-version → range; `link:`/`workspace:` dep → skipped; single-package repo; pnpm-list failure → empty
- [x] 3.3 Verified the new logic end-to-end against the real `pnpm.rb` via an isolated harness reproducing every spec scenario (all green). NOTE: full `bundle exec rspec` is blocked by a pre-existing `multi_json`/`google-apis` lockfile gap unrelated to this change (spec_helper requires the whole library, which pulls `google/apis/sheets_v4`). Re-run the bundler suite once that env issue is resolved.

## 4. Verify against jobber-frontend

- [x] 4.1 Ran the real `add_all_libraries` against live `pnpm list --depth=0 --json` from the `jobber-frontend` worktree: 0 blank versions across root/apps/jobber-online/packages/core; `wrangler`/`storybook` now populated
- [x] 4.2 Confirmed two workspaces produce different current-version sets (jobber-online=119 libs vs core=12) — per-workspace duplication is gone

## 5. Release

- [ ] 5.1 (Release-time follow-up) Bump the gem version + tag a new release, then advance `jobber-frontend` `bin/Gemfile`'s git tag to consume the fix. Deferred: requires a tag on the merged commit and a separate jobber-frontend-owned change.
