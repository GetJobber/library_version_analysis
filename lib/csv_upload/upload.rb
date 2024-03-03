require "library_version_analysis/library_tracking"
require "json"

module CsvUpload
  class Upload
    TYPE_SIGNATURES = {
      library: "#name,owner,current_version",
      new_version: "#name,new_version",
      vulnerability: "#library,identifier,assigned_severity,state",
    }.freeze

    def self.go(project:, csv_file:)
      puts "RUNNING"
      upload = Upload.new
      upload.upload(project: project, csv_file: csv_file)
    end

    def upload(project:, csv_file:)
      read_file(csv_file)

      results[:source] = "CSV"
      results[:repository] = project

      LibraryVersionAnalysis::LibraryTracking.upload(results.to_json)
    end

    def get_file(csv_file)
      File.open(csv_file, "r")
    end

    private

    def find_type(line)
      TYPE_SIGNATURES.each do |type, signature|
        return type if line.start_with?(signature)
      end

      return nil
    end

    def library(line)
      library, owner, current_version = line.split(",")

      results[:libraries] = [] unless results.has_key?(:libraries)
      results[:libraries] << { "name": library.strip, "owner": owner.strip, "version": current_version.strip }
    end

    def new_version(line)
      library, new_version = line.split(",")

      results[:new_versions] = [] unless results.has_key?(:new_versions)
      results[:new_versions] << { "name": library.strip, "version": new_version.strip }
    end

    def vulnerability(line)
      library, identifier, assigned_severity, state = line.split(",")

      results[:vulnerabilities] = [] unless results.has_key?(:vulnerabilities)
      results[:vulnerabilities] << { "library": library.strip, "identifier": identifier.strip, "assigned_severity": assigned_severity.strip, "state": state.strip}
    end

    def read_file(csv_file)
      file = get_file(csv_file)

      type = nil
      file.each do |line|
        next if line.strip.empty?
        if line.start_with?("#")
          type = find_type(line)
          if type.nil?
            puts "Could not find type with signature: #{line}"
            exit(-1)
          end

          next
        end

        send(type, line) if type
      end
    end

    def results
      @results ||= {}
    end
  end
end