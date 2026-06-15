# LibraryVersionAnalysis

This is unmaintained library being open sourced for others to learn and fork from.

Patches will not be accepted. Issues are not likely to be responded to.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'library_version_analysis'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install library_version_analysis

## Usage

```bash
analyze <repository> <source> [context]
```

| Argument | Description |
|----------|-------------|
| `repository` | The repository name (e.g., `jobber`) |
| `source` | The package manager: `gemfile`, `npm`, or `pnpm` |
| `context` | *(Optional, pnpm only)* A specific pnpm workspace to analyze |

### Examples

```bash
# Analyze all gems
analyze my-repo gemfile

# Analyze all npm packages
analyze my-repo npm

# Analyze all pnpm workspaces
analyze my-repo pnpm

# Analyze a specific pnpm workspace
analyze my-repo pnpm packages/ui
```

### The `context` parameter

When using the `pnpm` source, the tool analyzes all workspaces by default. The optional `context` argument filters analysis to a single workspace by name. If the provided workspace name doesn't match any discovered workspace, the tool prints the available workspaces and exits.

This parameter is ignored for `gemfile` and `npm` sources.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.
To use in development version of this code to analyze Jobber, replace the gem definition with  jgem :enablers, "library_version_analysis", path: "/Users/johnz/workspace/library_version_analysis"

## Updating Version Tag
TODO when I next update, but...

Also remember to update (maybe, we don't know why yet) the bundle_cache_key in circle-ci as per this PR: https://github.com/GetJobber/Jobber/pull/40468/files

## API Tokens
### Github
Used to read dependabot alerts

To create the github token:
1) Under you profile, go to settings
2) Now on the right side, click on Developer settings (near the bottom)
3) Click on Personal access tokens -> Tokens (classic)
4) Create a new classic token, selecting the (repo (all), read:package and read:project) scopes

### Upload Key
The key used by LibraryTracking. See that project for the correct value.

### Slack token
deprecated

## Jobber Dev
Update the gemfile to read:
jgem :enablers, "library_version_analysis", path: "/Users/johnz/source/library_version_analysis"

then: bundle update --conservative library_version_analysis
ln -s ../library_version_analysis .
source library_version_anaysis/version.sh
library_version_analysis/run.sh

## CI Pipeline Requirements for pnpm Workspaces

For pnpm workspace repositories (monorepos), the CI pipeline must generate per-workspace libyear files before running the analysis. Each workspace gets its own libyear file with a hyphen-based naming convention.

### File Naming Convention

| Workspace Path | Libyear Filename |
|---------------|------------------|
| Root (.) | `libyear_root.txt` |
| apps/client | `libyear_apps-client.txt` |
| apps/server | `libyear_apps-server.txt` |
| packages/ui | `libyear_packages-ui.txt` |
| Non-workspace repo | `libyear_report.txt` |

### Example CI Configuration (CircleCI/GitHub Actions)

```yaml
- name: Generate libyear reports
  run: |
    # Root workspace
    pnpx libyear --package-manager pnpm --json > libyear_root.txt
    
    # Each workspace (skip root at index 0)
    for workspace in $(pnpm list -r --depth=-1 --json | jq -r '.[1:] | .[].path'); do
      relative_path="${workspace#$(pwd)/}"
      filename="libyear_${relative_path//\//-}.txt"
      pnpx libyear --package-manager pnpm --json --cwd "$workspace" > "$filename" || true
    done

- name: Run library analysis
  run: ./exe/analyze $REPO_NAME pnpm
```

### Non-workspace Repositories

For non-workspace pnpm repositories (single package.json), continue using the existing single file approach:

```bash
pnpx libyear --package-manager pnpm --all --json > libyear_report.txt
```

## Library Tracking Server Integration

This gem uploads per-workspace data to the [library_tracking](https://github.com/GetJobber/library_tracking) Rails app via `POST /api/libraries/upload`.

### Upload Payload

For each pnpm workspace, the gem sends a separate upload with:

```json
{
  "source": "<workspace_name>",
  "repository": "<repository>",
  "libraries": [...],
  "new_versions": [...],
  "vulnerabilities": [...],
  "dependencies": [...]
}
```

| Field | Value | Example |
|-------|-------|---------|
| `repository` | The first CLI argument, passed through | `"jobber-frontend"` |
| `source` | The workspace name (root workspace becomes `"root"`, nested workspaces use their relative path) | `"root"`, `"packages/ui"` |

For non-workspace pnpm repos, `source` is `"pnpm"`. For other package managers, `source` matches the CLI argument (`"gemfile"`, `"npm"`).

### Database Disambiguation

The library_tracking database uniquely identifies a library by the composite index `(name, source, repository_id)`. This means the same library (e.g., `react`) can exist independently in multiple workspaces within the same repository, each tracked with its own version history, vulnerabilities, and dependency graph.

> **Note:** The [DB diagram](https://dbdiagram.io/d/versions-63dfe88e296d97641d7e9064) is outdated and does not show the `source` column on the `libraries` table. Refer to `db/schema.rb` in the [library_tracking repo](https://github.com/GetJobber/library_tracking) for the current schema.

## Contributing

Not supported

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
