require "library_version_analysis/ownership"
require "library_version_analysis/configuration"
require "code_ownership"

module LibraryVersionAnalysis
  class Poetry
    include LibraryVersionAnalysis::Ownership

    def initialize(github_repo)
      @github_repo = github_repo
    end

    def get_versions(source) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      parsed_results = {}
      meta_data = MetaData.new
      
      puts("\Poetry dependabot") if LibraryVersionAnalysis.dev_output?
      add_dependabot_findings(parsed_results, meta_data, @github_repo, source)

      puts("Poetry done") if LibraryVersionAnalysis.dev_output?

      return parsed_results, meta_data
    end

    def add_dependabot_findings(parsed_results, meta_data, github_repo, source)
      LibraryVersionAnalysis::Github.new.get_dependabot_findings(parsed_results, meta_data, github_repo, source)
    end
  end
end
