## Why

The LIBTRACK-136 fix (`3a76c5e`, "Fix blank pnpm current versions…") resolved current versions from structured `pnpm list --json`, so each workspace's own direct/dev dependencies now upload real versions. The reporter confirmed it got "better but not fully fixed": ~89% of uploaded rows for `jobber-frontend` (repository 34) still carry a blank version.

The remaining blanks are a **different defect that the prior fix explicitly scoped out** (its design.md lists "Changing libyear sourcing" as a Non-Goal). `Pnpm#parse_libyear` mints a standalone library record with an empty `current_version` for every dependency in the libyear report that is not in the analyzed workspace's resolved dependency set:

```ruby
vv = all_libraries[line["dependency"]]
if vv.nil?
  vv = new_version_line("")          # blank current_version
  all_libraries[line["dependency"]] = vv
end
```

This is fatal in `jobber-frontend` because the "per-workspace" `libyear_<ws>.txt` files are actually the **merged union of every workspace's direct dependencies**: libyear 0.8.0 runs `pnpm list --depth=0 --json` and lodash-`merge`s all project objects together, and its JSON omits the installed version entirely (only `dependency, drift, pulse, releases, major, minor, patch, available`). So every one of the 24 workspaces is uploaded ~248 foreign packages that do not belong to it, each with a blank version.

Evidence — Jun 10 nightly (post-fix) CSV, repository 34:

- 6,725 rows; **5,975 (89%) blank version**.
- The blank set is a near-constant ~248 names present in **every** workspace.
- Each name carries a real version only in the 1–3 workspaces where it is genuinely a dependency (e.g. `@fullcalendar/core` → versioned in `apps/jobber-online`, blank in 24 others).

## What Changes

- Restrict the libraries carried into the upload to the **analyzed workspace's resolved dependency set**. libyear data SHALL only enrich libraries already resolved from that workspace's `pnpm list --json` output (`add_all_libraries`). libyear-reported dependencies that are absent from the workspace SHALL NOT be added as standalone library records.
- Implementation: snapshot the resolved workspace package names from `add_all_libraries` **before** `parse_libyear` runs, then filter `parsed_results` down to that set — extending the existing `filter_to_workspace_packages` (which today only removes Dependabot-injected names; its snapshot is taken *after* `parse_libyear`, so the libyear bleed is already "known" and survives).
- Preserve everything the prior fix established: per-workspace current-version resolution (`3a76c5e`), libyear latest-version/drift enrichment for in-workspace libraries, the `a..b` multi-version range form, and vulnerability / dependency-graph handling for retained libraries.

## Capabilities

### Modified Capabilities

- `pnpm-version-analysis`: adds the constraint that uploaded libraries are limited to the analyzed workspace's resolved dependencies, so libyear's whole-monorepo report cannot introduce foreign, version-less library records.

## Impact

- **Code**: `lib/library_version_analysis/pnpm.rb` — capture the resolved workspace package set before `parse_libyear`; extend `filter_to_workspace_packages` to drop libyear-only entries. Callers `get_versions` (single-package) and `get_versions_for_workspace` (monorepo).
- **Behavior**: per-workspace uploads carry only that workspace's real dependencies, each with a version. Blank-version rows stop being produced. The ~248-foreign-package-per-workspace mis-attribution is eliminated.
- **Tests**: `spec/pnpm_spec.rb` — cover that libyear-only deps are dropped, and that in-workspace deps appearing in libyear are retained and enriched (current + latest version).
- **Prerequisite — new branch**: this change must be built on a branch cut from latest `origin/master`, which includes fix `3a76c5e` and the OpenSpec scaffolding. The prior task worktree branch (`46292689…`) predates both and has no `openspec/` directory. This proposal was authored on `libtrack-136-scope-libyear-deps-to-workspace` (off `origin/master`).
- **Companion change (separately owned)**: a code fix does not retroactively clean rows already in Library Tracking. Existing blank/foreign rows are addressed by the `library_tracking` change `cleanup-blank-library-versions`.
- **Related, out of scope**: the same blank-minting `parse_libyear` pattern exists in `npm.rb` and `gemfile.rb` (other repos/sources). Not changed here; noted for follow-up.
