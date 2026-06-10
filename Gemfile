source "https://rubygems.org"

# Specify your gem's dependencies in library_version_analysis.gemspec
gemspec

gem "rspec", "~> 3.0"
gem "graphql", "~> 2.4.8"
gem "graphql-client", "~> 0.18"

# multi_json is declared as a runtime dependency in the gemspec (representable, pulled in via
# google-api-client, requires it at runtime without declaring it). It is intentionally not
# repeated here so the gemspec remains the single source of truth for gem consumers.

plugin "bundler-why"
