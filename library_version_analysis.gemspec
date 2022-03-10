require_relative 'lib/library_version_analysis/version'

Gem::Specification.new do |spec|
  spec.name          = "library_version_analysis"
  spec.version       = LibraryVersionAnalysis::VERSION
  spec.authors       = ["Jobber"]
  spec.email         = ["info@getjobber.com"]

  spec.summary       = 'Analysis library versions (ruby and npm) and reports on out-of-date libraries (with ownership).'
  spec.description   = 'Analysis library versions (ruby and npm) and reports on out-of-date libraries (with ownership).'
  spec.homepage      = "https://github.com/GetJobber/library_version_analysis"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.5.0")

  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/GetJobber/library_version_analysis"
  spec.metadata["changelog_uri"] = "https://github.com/GetJobber/library_version_analysis/CHANGELOG.MD"

  spec.add_dependency 'google-api-client', '~> 0.27'
  spec.add_dependency "googleauth", "0.10.0"
  spec.add_dependency "libyear-bundler", "~> 0.6.0"
  spec.add_dependency "open3", "~> 0.1.1"
  spec.add_dependency "pry", "~> 0.13.1"
  spec.add_dependency 'pry-byebug', "~> 3.9.0"

  spec.add_development_dependency "rspec", "~> 3.2"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
