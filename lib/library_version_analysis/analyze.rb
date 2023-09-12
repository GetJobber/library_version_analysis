module LibraryVersionAnalysis
  class Analyze
    def self.go(repository)
      spreadsheet_id = ENV["VERSION_STATUS_SPREADSHEET_ID"]

      results = LibraryVersionAnalysis::CheckVersionStatus.run(spreadsheet_id: spreadsheet_id, repository: repository, source: "RUBYGEMS")

      merged_result = {}
      results.keys.each { |key| merged_result.merge!(results[key]) }

      metrics = {
        online_version_status: merged_result,
      }

      return metrics
    end
  end
end
