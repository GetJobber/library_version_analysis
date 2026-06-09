source "https://rubygems.org"

# Specify your gem's dependencies in library_version_analysis.gemspec
gemspec

gem "rspec", "~> 3.0"
gem "graphql", "~> 2.4.8"
gem "graphql-client", "~> 0.18"

# representable (pulled in via google-api-client) requires "multi_json" at
# runtime but does not declare it as a dependency, so bundler omits it and
# loading google/apis/sheets_v4 fails with "multi_json is not part of the bundle".
gem "multi_json"

plugin "bundler-why"
