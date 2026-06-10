## ADDED Requirements

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

#### Scenario: Resolved set unavailable

- **WHEN** the analyzed workspace's resolved dependency set cannot be determined (e.g. `pnpm list --json` failed and returned no data)
- **THEN** the system SHALL NOT drop all libraries as out-of-scope, and SHALL instead skip the workspace-scope restriction and log that it was skipped
