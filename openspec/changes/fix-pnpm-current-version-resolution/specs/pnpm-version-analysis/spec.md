## ADDED Requirements

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
