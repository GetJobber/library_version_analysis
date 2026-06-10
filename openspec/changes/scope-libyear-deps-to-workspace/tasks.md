## 0. Prerequisite — branch

- [x] 0.1 Ensure work is on a branch cut from latest `origin/master` (includes fix `3a76c5e` + OpenSpec scaffolding). This change was authored on `libtrack-136-scope-libyear-deps-to-workspace`; do not implement on the pre-fix task worktree branch (`46292689…`), which has no `openspec/`.

## 1. Confirm the resolved-set vs libyear-set gap

- [ ] 1.1 From a `jobber-frontend` worktree, capture `add_all_libraries` output for a small workspace (e.g. `packages/tsconfig`) and that workspace's `libyear_packages-tsconfig.txt`; confirm libyear lists ~248 names while the resolved set lists only that workspace's deps. _(Pending live capture; the union behavior was confirmed from libyear 0.8.0 source + the CSV.)_
- [x] 1.2 Confirm the blank rows in the CSV correspond exactly to `libyear_names − resolved_names` for each workspace. _(Confirmed during exploration: 5,975 blank rows; a near-constant ~248-name set blank in every workspace, each name versioned only in the 1–3 workspaces where it is a real dependency.)_

## 2. Scope the upload to the resolved workspace set

- [x] 2.1 In `Pnpm#get_versions_for_workspace` and `Pnpm#get_versions`, snapshot the resolved workspace package names from `add_all_libraries` **before** calling `parse_libyear` (the authoritative per-workspace set).
- [x] 2.2 Extend `filter_to_workspace_packages` so the post-merge filter uses that pre-`parse_libyear` snapshot, dropping both libyear-only and Dependabot-only names that are not in the resolved set.
- [x] 2.3 Guard the empty case: if the resolved set is empty (e.g. `pnpm list` failed / returned `nil`), skip the libyear-scope filter and log, rather than uploading an empty library list.
- [x] 2.4 Confirm `parse_libyear` is unchanged and aggregate `meta_data` (computed before filtering) is unaffected.

## 3. Tests

- [x] 3.1 In `spec/pnpm_spec.rb`, add coverage: a libyear report containing a name **not** in the resolved set is dropped (no blank-version record).
- [x] 3.2 A name present in **both** the resolved set and libyear is retained and carries current version + libyear `available`/major/minor/patch.
- [x] 3.3 Per-workspace distinctness preserved: a dependency of workspace A does not appear in workspace B's results via libyear.
- [x] 3.4 Empty-resolved-set guard: filter is skipped and analysis does not abort.
- [x] 3.5 `bundle exec rspec` passes. _(120 examples, 0 failures — 116 prior + 4 new.)_

## 4. Verify against jobber-frontend

- [ ] 4.1 Run analysis for ≥2 workspaces and confirm zero blank `current_version` entries in the upload payload (`server_data`) and that each workspace's library set matches its own resolved deps.
- [ ] 4.2 Spot-check that previously-foreign names (e.g. `@fullcalendar/core` in `packages/tsconfig`) are absent from workspaces where they are not dependencies.

## 5. Release & rollout

- [ ] 5.1 (Release-time follow-up) Bump the gem version + tag a release, then advance `jobber-frontend` `bin/Gemfile`'s git tag to consume the fix (separate `jobber-frontend`-owned change).
- [ ] 5.2 Coordinate with the `library_tracking` `cleanup-blank-library-versions` change so existing blank/foreign rows are cleaned after the new analyzer has run at least once.
