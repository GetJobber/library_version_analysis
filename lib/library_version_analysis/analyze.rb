module LibraryVersionAnalysis
  class Analyze
    def self.go(repository)
      results = LibraryVersionAnalysis::CheckVersionStatus.run(repository: repository)

      merged_result = {}
      results.keys.each { |key| merged_result.merge!(results[key]) }

      metrics = {
        online_version_status: merged_result,
      }

      return metrics
    end
  end
end
