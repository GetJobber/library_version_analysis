module LibraryVersionAnalysis
  class Analyze
    def self.respond()
      puts "Do that Analyze"
      return "Do that Analyze"
    end

    def self.go
      spreadsheet_id = ENV["VERSION_STATUS_SPREADSHEET_ID"]
      results = LibraryVersionAnalysis::CheckVersionStatus.run(spreadsheet_id: spreadsheet_id, online: "true", online_node: "true", mobile: "false")

      merged_result = {}
      results.keys.each { |key| merged_result.merge!(results[key]) }

      metrics = {
        online_version_status: merged_result,
      }

      return metrics
    end
  end
end