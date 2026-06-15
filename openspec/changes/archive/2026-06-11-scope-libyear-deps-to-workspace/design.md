## Context

After `3a76c5e`, `Pnpm` resolves current versions per workspace from `pnpm list --depth=0 --json` in `add_all_libraries`, then `parse_libyear` merges libyear latest-version/drift data, then `server_data` uploads `libraries[].version = row.current_version`.

Two facts about the libyear input make `parse_libyear` produce blank-version, foreign library records:

1. **libyear carries no installed version.** libyear 0.8.0's JSON per dependency is `{ dependency, drift, pulse, releases, major, minor, patch, available }` — `available` is the latest version; there is no installed/current field. So `parse_libyear` cannot populate `current_version` and never tries; for any dependency not already in `all_libraries` it inserts `new_version_line("")`.
2. **The "per-workspace" libyear files are the whole-monorepo union.** libyear runs `pnpm list --depth=0 --json` and lodash-`merge`s all project objects, so `libyear_<ws>.txt` for every workspace contains the union (~248) of all workspaces' direct dependencies. `add_all_libraries`, by contrast, correctly resolves only the analyzed workspace's deps.

The mismatch: `parse_libyear` injects ~248 names into every workspace; only the handful that intersect that workspace's resolved set carry a current version, and the rest upload blank.

The existing `filter_to_workspace_packages` does not help, because its "known" snapshot is taken **after** `parse_libyear`:

```ruby
parsed_results, meta_data = parse_libyear(libyear_results, all_libraries)
workspace_package_names = parsed_results.keys.to_set   # already includes the libyear union
add_dependabot_findings(...)
filter_to_workspace_packages(parsed_results, workspace_package_names, source)  # only strips Dependabot adds
```

## Goals / Non-Goals

**Goals**
- Stop uploading library records for dependencies that are not in the analyzed workspace's resolved dependency set.
- Eliminate blank `current_version` rows for pnpm repos that arise from libyear-only dependencies.
- Preserve per-workspace current-version resolution, libyear enrichment of in-workspace libraries, the `a..b` range form, and vulnerability/dependency-graph handling.

**Non-Goals**
- Changing how libyear files are generated in `jobber-frontend` (the "option B" source fix). Considered and deferred — see Decisions.
- Backfilling current versions for transitive or other-workspace dependencies (they should not be uploaded per-workspace as standalone libraries).
- Cleaning existing rows in Library Tracking (separate `library_tracking`-owned change).
- The equivalent `parse_libyear` pattern in `npm.rb` / `gemfile.rb`.

## Decisions

**1. Scope the upload to the resolved workspace set (option A), in the gem.**
Snapshot `all_libraries.keys` returned by `add_all_libraries` (the authoritative resolved dependency set for the analyzed workspace) **before** calling `parse_libyear`, then filter `parsed_results` to that set after the libyear merge and Dependabot injection. libyear continues to enrich libraries that are in the set; libyear-only names are dropped instead of uploaded blank.

Rationale: the resolved set from `pnpm list --json` is already correct and authoritative per workspace (that is exactly what `3a76c5e` fixed). Filtering to it removes both the blank versions and the cross-workspace mis-attribution in one move, entirely within the gem, with no dependency on libyear's generation behavior.

**2. Implement by extending `filter_to_workspace_packages`, not rewriting `parse_libyear`.**
Move/duplicate the snapshot so it captures the resolved set before `parse_libyear`, and reuse the existing filter to delete out-of-set names. Keeps `parse_libyear` unchanged (it still safely enriches; any entries it adds get filtered out afterward), and unifies libyear-bleed removal with the Dependabot-bleed removal the filter already does.

**2a. Distinguish "could not determine the resolved set" from "resolved but empty".**
`add_all_libraries` returns `nil` when the resolved set cannot be determined (pnpm list failed, unparseable output, or no matching workspace entry) and an (possibly empty) hash on success. The caller snapshots `resolved&.keys&.to_set` (so `nil` propagates) and `filter_to_workspace_packages` skips only when the snapshot is `nil`. An **empty** set still filters — dropping the whole-monorepo libyear union for a workspace that genuinely has no registry-versioned direct deps (e.g. `link:`-only packages like `packages/tsconfig`). Local validation against `jobber-frontend` proved this matters: without the distinction, `apps/harbour`, `packages/tsconfig`, and `packages/graphql-depth-limit-plugin` each re-emitted the full ~215-entry union as blanks; with it, they correctly contribute zero libraries and all 24 workspaces report 0 blank versions.

**3. Option B (per-workspace libyear at the source) rejected for this change.**
Making `libyear_<ws>.txt` genuinely per-workspace would require working around libyear 0.8.0's `pnpm list --json` + `merge(...)` union behavior in `jobber-frontend`, is cross-repo and more invasive, and still would not retroactively fix data. Option A fixes the ticket symptom and the mis-attribution with a smaller, gem-local blast radius. Option B remains a reasonable future data-pipeline cleanup but is not required.

**4. Empty current versions remain valid only for in-workspace deps.**
A dependency that is in the workspace's resolved set but has no semver (e.g. `link:` / `workspace:` — already skipped by `current_version_from_info`) is governed by existing spec behavior. The new constraint only removes records for names absent from the resolved set; it does not change handling of in-workspace deps.

## Risks / Trade-offs

- **Outdated transitive or other-workspace deps are no longer surfaced per workspace.** This is intended: they are not dependencies of the analyzed workspace and were previously uploaded as blank-version noise. Aggregate libyear metrics (`meta_data`) are computed in `parse_libyear` before filtering and are unaffected.
- **Reliance on `add_all_libraries` correctness.** Filtering to the resolved set means a mis-resolution would drop libraries. Mitigated by the `nil` (could-not-determine → skip) vs empty (resolved-but-empty → filter) distinction in Decision 2a: a pnpm failure preserves prior behavior instead of wiping, while a genuinely empty workspace correctly drops the foreign union.
- **A workspace with deps that fail to install locally resolves to empty and contributes zero libraries.** Observed for `apps/harbour` in a partial local worktree (`pnpm list --depth=0 --json` returned no installed deps). This is the safe outcome (zero rows beats blank rows); in CI with a full install the workspace resolves its real deps normally.
