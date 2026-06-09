## Context

`Pnpm#add_all_libraries` populates `Versionline#current_version` for every dependency before `parse_libyear` merges in latest-version/drift data and `server_data` uploads `libraries[].version` to Library Tracking. Today it shells out to `pnpm list --depth=0 --silent` and parses the **rendered text** with two regexes:

```ruby
scan_result = line.scan(/^.*?\s([@\w][^\s]+)\s([.\d]+)/)        # "<prefix> name version"
scan_result = line.scan(/^.*?\s([@\w].+)@([.\d]+)/) if empty    # "<prefix> name@version"
```

Both begin with `^.*?\s`, so they only match when a package line has a leading prefix (the `├── ` tree connector) before the name. In CI (non-TTY) pnpm emits bare `name@version` lines without that prefix, so both regexes fail and `current_version` is left blank for ~all libraries — the symptom in LIBTRACK-136. The nightly upload log confirms every library uploads as `name @ <blank>`.

Two further problems live in the same path:
- `add_all_libraries(workspace_path)` runs `pnpm list --dir <workspace_path> ...`, but pnpm resolves `--dir` to the workspace **root**, so all 24 workspaces are analyzed against identical root data.
- The repo already has a structured alternative: `run_pnpm_list` calls `pnpm list ... --json` and `add_dependency_graph` walks the parsed object's `dependencies` / `devDependencies`.

## Goals / Non-Goals

**Goals:**
- Populate `current_version` reliably for pnpm repos, independent of terminal rendering, so CI and local runs agree.
- Make per-workspace current-version resolution actually reflect the analyzed workspace.
- Preserve the existing contract: libyear merge (`parse_libyear`), the `a..b` range form (`calculate_version`), and the uploaded `version` field shape.

**Non-Goals:**
- Changing libyear sourcing, dependency-graph construction, ownership, or the upload payload schema.
- Fixing `jobber-frontend`'s TS analyzer JSON-extraction failure (separate, jobber-frontend-owned).
- Changing the npm or gemfile analyzers.

## Decisions

**1. Resolve current versions from `pnpm list --json` instead of rendered text.**
Parse the JSON and read each package's `version` field from the project's `dependencies` and `devDependencies` maps. Rationale: the JSON `version` is the resolved semver string with no tree connectors, peer-suffix decoration, or TTY dependence — eliminating the entire regex-format failure class. Alternative considered: harden the regex (e.g. tolerate missing prefix). Rejected — it chases pnpm's rendering choices and remains brittle; structured output is already used elsewhere in this file.

**2. Reuse the existing JSON invocation.**
`run_pnpm_list(workspace_path)` already returns `pnpm list ... --json`. Source current versions from the same call rather than introducing a second `pnpm list` shape. This also unifies how the workspace is selected.

**3. Select the correct workspace from the JSON.**
`pnpm list --json` returns an array of project objects. Choose the entry corresponding to the analyzed `workspace_path` (match on its `path`/`name`) and read that entry's `dependencies`/`devDependencies`, rather than relying on `--dir` (which collapses to root). Rationale: fixes the per-workspace duplication with the data already in hand.

**4. Keep merge and range semantics.**
Continue returning a `{ name => Versionline }` map so `parse_libyear` is unchanged. When a name appears with multiple resolved versions, keep combining via `calculate_version` to produce the `a..b` range. Packages with non-semver specifiers (`link:`, `workspace:`) resolve to an empty current version, matching prior intent for unversioned local links.

## Risks / Trade-offs

- **JSON field shape differs from assumptions** → Validate against real `pnpm list --json` for `jobber-frontend` (root + a workspace) during implementation; cover scoped names, `link:` deps, and multi-version packages in specs.
- **Workspace-selection ambiguity (root vs. a package sharing a path prefix)** → Match the workspace entry exactly by its resolved path/name; fall back explicitly and log when no entry matches rather than silently using root.
- **Behavior change in `current_version` values** (previously blank, now populated; ranges may appear) → This is the intended fix; note it so Library Tracking consumers expect populated versions and occasional `a..b` ranges.
- **`add_all_libraries` is stubbed in current tests** → Add focused unit coverage so the JSON path is actually exercised, not mocked away.

## Migration Plan

No data migration. The next nightly `static_analysis` run uploads populated versions, overwriting the blank values currently stored. Rollback = revert the change; the prior (blank-version) behavior returns. No schema or config changes required.
