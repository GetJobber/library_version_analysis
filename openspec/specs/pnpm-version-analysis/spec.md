# pnpm-version-analysis Specification

## Purpose
TBD - created by archiving change fix-pnpm-current-version-resolution. Update Purpose after archive.
## Requirements
### Requirement: Resolve current versions from structured pnpm output

The system SHALL determine each dependency's installed ("current") version by reading the structured `version` field from `pnpm list`'s JSON output, and SHALL NOT depend on the rendered text/tree formatting of `pnpm list`.

#### Scenario: Plain dependency version

- **WHEN** a pnpm project has a dependency `@apollo/client` resolved to `3.13.8`
- **THEN** the resolved current version for `@apollo/client` SHALL be `3.13.8`

#### Scenario: Scoped and unscoped names

- **WHEN** the project includes both a scoped package (e.g. `@datadog/datadog-api-client`) and an unscoped package (e.g. `wrangler`)
- **THEN** the current version SHALL be resolved for both, keyed by their full package names

#### Scenario: Output rendering does not affect results

- **WHEN** pnpm is invoked in a non-interactive (non-TTY) environment such as CI
- **THEN** the resolved current versions SHALL be identical to those produced in an interactive environment for the same installed dependency tree

### Requirement: Current versions reflect the analyzed workspace

The system SHALL resolve current versions from the specific workspace being analyzed, using that workspace's `dependencies` and `devDependencies`, so that per-workspace results are distinct.

#### Scenario: Per-workspace direct dependencies

- **WHEN** workspace `apps/jobber-online` declares `storybook` and workspace `packages/core` does not
- **THEN** the current version for `storybook` SHALL be present in the `apps/jobber-online` results and absent from the `packages/core` results

#### Scenario: Workspaces are not collapsed to the repository root

- **WHEN** analyzing a multi-workspace pnpm monorepo
- **THEN** each workspace's resolved current-version set SHALL be derived from that workspace and SHALL NOT be uniformly replaced by the repository root's dependency set

### Requirement: Preserve downstream version handling

The system SHALL continue to merge resolved current versions with libyear data and SHALL preserve the existing representation of a current version, including the range form used when a dependency resolves to more than one version.

#### Scenario: Merge with libyear-tracked library

- **WHEN** a library appears in both the resolved current versions and the libyear report
- **THEN** the uploaded record SHALL carry the resolved current version alongside the libyear-provided latest version

#### Scenario: Multiple resolved versions for one package

- **WHEN** a package resolves to more than one version across the analyzed set (e.g. `4.54.0` and `4.76.0`)
- **THEN** the current version SHALL be expressed as a range (`4.54.0..4.76.0`) consistent with the existing version-combining behavior

#### Scenario: Library with no resolvable current version

- **WHEN** a tracked library has no resolvable installed version (e.g. a workspace `link:` dependency)
- **THEN** the system SHALL record an empty current version for that library without aborting analysis of the remaining libraries

### Requirement: Tracked libraries are limited to the analyzed workspace's dependencies

The system SHALL upload library records only for dependencies present in the analyzed workspace's resolved dependency set (the `dependencies` and `devDependencies` resolved from that workspace's `pnpm list --json`). Dependencies that appear only in the libyear report — including dependencies that belong to other workspaces because the libyear report spans the whole monorepo — SHALL NOT be added as standalone library records.

#### Scenario: libyear report includes dependencies from other workspaces

- **WHEN** the libyear report used for workspace `packages/tsconfig` includes `@fullcalendar/core`, which is a dependency of `apps/jobber-online` and not of `packages/tsconfig`
- **THEN** `@fullcalendar/core` SHALL NOT appear as a library record in the `packages/tsconfig` results

#### Scenario: No blank-version records from libyear-only dependencies

- **WHEN** the libyear report contains a dependency that has no entry in the analyzed workspace's resolved dependency set
- **THEN** the system SHALL NOT create a library record with an empty current version for that dependency

#### Scenario: In-workspace dependency present in libyear is retained and enriched

- **WHEN** a dependency is in both the analyzed workspace's resolved dependency set and the libyear report
- **THEN** its library record SHALL be retained and SHALL carry both the resolved current version and the libyear-provided latest version

#### Scenario: Workspace genuinely has no resolvable direct dependencies

- **WHEN** the analyzed workspace is resolved successfully but has no registry-versioned direct dependencies (e.g. only `link:`/`workspace:` deps, or none)
- **THEN** the workspace-scope restriction SHALL still apply, so libyear-reported dependencies from other workspaces SHALL be dropped and the workspace SHALL contribute no version-less library records

#### Scenario: Resolved set cannot be determined

- **WHEN** the analyzed workspace's resolved dependency set cannot be determined (e.g. `pnpm list --json` failed, returned unparseable output, or contained no matching workspace entry)
- **THEN** the system SHALL distinguish this from an empty-but-resolved set, SHALL NOT drop all libraries as out-of-scope, and SHALL instead skip the workspace-scope restriction and log that it was skipped

