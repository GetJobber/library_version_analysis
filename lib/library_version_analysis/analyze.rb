module LibraryVersionAnalysis
  class Analyze

    def self.go(repository, source)
      results = LibraryVersionAnalysis::CheckVersionStatus.run(repository: repository, source: source)

      merged_result = {}
      results.keys.each { |key| merged_result.merge!(results[key]) }

      metrics = {
        online_version_status: merged_result,
      }

      return metrics
    end
  end
end
