require "googleauth"
require "google/apis/sheets_v4"
require "pry-byebug"
require "library_version_analysis/library_tracking"
require "library_version_analysis/configuration"

module LibraryVersionAnalysis
  Versionline = Struct.new(
    :owner,
    :owner_reason,
    :parent,
    :current_version,
    :current_version_date,
    :latest_version,
    :latest_version_date,
    :vulnerabilities,
    :major,
    :minor,
    :patch,
    :age,
    # :source,
    :dependency_graph,
    keyword_init: true
  )

  Vulnerability = Struct.new(:identifier, :state, :fixed_at, :permalink, :assigned_severity, keyword_init: true)
  MetaData = Struct.new(:total_age, :total_releases, :total_major, :total_minor, :total_patch, :total_cvss)
  ModeSummary = Struct.new(:one_major, :two_major, :three_plus_major, :minor, :patch, :total, :total_lib_years, :total_cvss, :unowned_issues, :one_number)

  LibNode = Struct.new(
    :name,
    :parents,
    keyword_init: true
  ) do |_|
    def deep_to_h
      h = {}
      h[:name] = name
      h[:parents] = parents&.map(&:deep_to_h)
      h
    end
  end

  def self.dev_output?
    ENV["DEV_OUTPUT"]&.downcase == "true"
  end

  OBFUSCATE_WORDS = false # This is to ensure we don't store actual spicy data except in secure prod DB

  class CheckVersionStatus
    # TODO: joint - Need to change Jobbers https://github.com/GetJobber/Jobber/blob/dea12cebf8e6c65b2cafb5318bd42c1f3bf7d7a3/lib/code_analysis/code_analyzer/online_version_analysis.rb#L6 to run three times. One for each.
    def self.run(spreadsheet_id: "", repository: "", source: "")
      # check for env vars before we do anything
      keys = %w(WORD_LIST_RANDOM_SEED GITHUB_READ_API_TOKEN LIBRARY_UPLOAD_URL UPLOAD_KEY)
      missing_keys = keys.reject { |key| !ENV[key].nil? && !ENV[key].empty? }

      raise "Missing ENV vars: #{missing_keys}" if missing_keys.any?

      c = CheckVersionStatus.new
      mode_results = c.go(spreadsheet_id: spreadsheet_id, repository: repository, source: source)

      mode_key = "#{repository}/#{source}"

      # ugly hack for legacy
      case mode_key
        when "jobber/npm"
          result_key = :online_node
        when "jobber/gemfile"
          result_key = :online
        when "jobber/mobile"
          result_key = :mobile
        else
          result_key = mode_key
      end

      results = {result_key =>  c.mode_results_specific(mode_results, mode_key.to_sym)}
      return results
    end

    def initialize
      LibraryVersionAnalysis::Configuration.configure

      if OBFUSCATE_WORDS # rubocop:disable Style/GuardClause
        @word_list = []

        File.open("/usr/share/dict/words").each { |line| @word_list << line.strip }
        @word_list.shuffle!(random: Random.new(ENV["WORD_LIST_RANDOM_SEED"].to_i))
        @word_list_length = @word_list.length
      end
    end

    def obfuscate(data)
      idx = data.sum % @word_list_length
      # return "#{data}:#{@word_list[idx]}" # note: the colon is required in the dependency graph obfuscation
      return ":#{@word_list[idx]}" # note: the colon is required in the dependency graph obfuscation
    end

    def go(spreadsheet_id:, repository:, source:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength

      if spreadsheet_id.nil? || spreadsheet_id.empty?
        @update_server = true
        @update_spreadsheet = false
        variant = "lt"
      else
        @update_server = false
        @update_spreadsheet = true
        variant = "legacy"
      end

      puts "Check Version #{variant}" if LibraryVersionAnalysis.dev_output?

      case source
      when "npm"
        meta_data, mode = go_npm(spreadsheet_id, repository, source)
      when "gemfile"
        meta_data, mode = go_gemfile(spreadsheet_id, repository, source)
      else
        puts "Don't recognize source #{source}"
        exit(-1)
      end

      print_summary(source, meta_data, mode) if LibraryVersionAnalysis.dev_output?

      puts "Done" if LibraryVersionAnalysis.dev_output?

      return {
        "#{repository}/#{source}": mode,
      }
    end

    def go_gemfile(spreadsheet_id, repository, source)
      puts "  gemfile" if LibraryVersionAnalysis.dev_output?
      gemfile = Gemfile.new(repository)

      meta_data, mode = get_version_summary(gemfile, "OnlineVersionData!A:Q", spreadsheet_id, repository, source)

      return meta_data, mode
    end

    def go_npm(spreadsheet_id, repository, source)
      puts "  npm" if LibraryVersionAnalysis.dev_output?
      npm = Npm.new(repository)

      if repository == "jobber" # ugly legacy hack
        range = "OnlineNodeVersionData!A:Q"
      else
        range = "MobileVersionData!A:Q"
      end

      meta_data, mode = get_version_summary(npm, range, spreadsheet_id, repository, source)

      return meta_data, mode
    end

    def get_version_summary(parser, range, spreadsheet_id, repository, source)
      parsed_results, meta_data = parser.get_versions(source)
      mode = get_mode_summary(parsed_results, meta_data)

      if @update_spreadsheet
        puts "    updating spreadsheet #{source}" if LibraryVersionAnalysis.dev_output?
        data = spreadsheet_data(parsed_results, repository, source)
        update_spreadsheet(spreadsheet_id, range, data)
      end

      if @update_server
        puts "    updating server" if LibraryVersionAnalysis.dev_output?
        data = server_data(parsed_results, repository, source).to_json
        LibraryTracking.upload(data)
      end

      puts "All Done!" if LibraryVersionAnalysis.dev_output?

      return meta_data, mode
    end

    # represents a single number summary of the state of the libraries
    def one_number(mode_summary)
      return mode_summary.three_plus_major * 50 + mode_summary.two_major * 20 + mode_summary.one_major * 10 + mode_summary.minor + mode_summary.patch * 0.5
    end

    def server_data(results, repository, source) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      libraries = []
      new_versions = []
      vulns = []
      dependencies = []

      puts("\tPURGING NPM dependency graph data") if LibraryVersionAnalysis.dev_output? && repository == "jobber-mobile" # This might be temporary. The dependency graph is too big.

      missing_dependency_keys = [] # TODO: handle missing keys
      results.each do |real_name, row|
        name = OBFUSCATE_WORDS ? obfuscate(real_name) : real_name

        libraries.push({name: name, owner: row.owner, owner_reason: row.owner_reason, version: row.current_version})
        row.vulnerabilities&.each do |vuln|
          permalink = OBFUSCATE_WORDS ? "https://github.com/advisories" : vuln.permalink
          identifier = OBFUSCATE_WORDS ? "\"GHSA-XXX\", \"CVE-XXX\"" : vuln.identifier.join(", ")
          vulns.push({library: name, identifier: identifier, assigned_severity: vuln.assigned_severity, url: permalink, state: vuln.state, fixed_at: vuln.fixed_at})
        end

        new_versions.push({name: name, version: row.latest_version, major: row.major, minor: row.minor, patch: row.patch}) unless row.latest_version.nil?

        if row.dependency_graph.nil? || repository == "jobber-mobile" #Not using the dependency graph for jobber-mobile might be temporary. It is currently too big.
          missing_dependency_keys.push(name)
        else
          dependency_graph = OBFUSCATE_WORDS ? obfuscate_dependency_graph([row.dependency_graph]).first : row.dependency_graph
          dependencies.push(dependency_graph.deep_to_h)
        end
      end

      {
        source: source.downcase,
        repository: repository,
        libraries: libraries,
        new_versions: new_versions,
        vulnerabilities: vulns,
        dependencies: dependencies,
      }
    end

    def obfuscate_dependency_graph(dependency_graph)
      return if dependency_graph.nil?

      dependency_graph.each do |dependency|
        next if dependency.name.include?(":") # If there is alrady a colon, it is already obfuscated
        dependency.name = obfuscate(dependency.name)
        dependency.parents = obfuscate_dependency_graph(dependency.parents)
      end
    end

    def spreadsheet_data(results, repository, source)
      header_row = %w(name owner parent source current_version current_version_date latest_version latest_version_date major minor patch age cve note cve_label cve_severity note_lookup_key)
      data = [header_row]

      case source
      when "npm"
        if repository == "jobber" # ugly legacy hack
          legacy_source= "ONLINE NODE"
        else
          legacy_source= "MOBILE"
        end
      when "gemfile"
        legacy_source= "ONLINE"
      else
        legacy_source= "UNKNOWN"
      end

      data << ["Updated: #{Time.now.utc}"]

      results.each do |name, row|
        vuln = row.vulnerabilities.nil? ? nil:row.vulnerabilities.select { |v| v.state != "FIXED" }.first
        if vuln.nil?
          cvss = nil
        else
          cvss = "#{vuln.assigned_severity}#{vuln.identifier}"
        end

        data << [
          name,
          row.owner,
          row.parent,
          legacy_source,
          row.current_version,
          row.current_version_date,
          row.latest_version,
          row.latest_version_date,
          row.major,
          row.minor,
          row.patch,
          row.age,
          cvss,
          '=IFERROR(concatenate(vlookup(indirect("Q" & row()),Notes!A:E,4,false), ":", concatenate(vlookup(indirect("Q" & row()),Notes!A:E,5,false))))',
          '=IFERROR(vlookup(indirect("Q" & row()),Notes!A:E,4,false), IFERROR(trim(LEFT(INDIRECT("Q" & row()), SEARCH("[", INDIRECT("M" & row()))-1))))',
          '=IFERROR(vlookup(indirect("O" & row()),\'Lookup data\'!$A$2:$B$6,2,false))',
          '=IF(ISBLANK(indirect("M" & row())), indirect("A" & row()), indirect("M" & row()))',
        ]
      end

      return data
    end

    def update_spreadsheet(spreadsheet_id, range_name, results)
      service = Google::Apis::SheetsV4::SheetsService.new
      service.authorization = ::Google::Auth::ServiceAccountCredentials.make_creds(scope: "https://www.googleapis.com/auth/spreadsheets")

      clear_range = Google::Apis::SheetsV4::BatchClearValuesRequest.new
      clear_range.ranges = [range_name]
      service.batch_clear_values(spreadsheet_id, clear_range)

      value_range_object = Google::Apis::SheetsV4::ValueRange.new(range: range_name, values: results)
      service.update_spreadsheet_value(spreadsheet_id, range_name, value_range_object, value_input_option: "USER_ENTERED")
    end

    def get_mode_summary(results, meta_data) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      mode_summary = ModeSummary.new
      mode_summary.one_major = 0
      mode_summary.two_major = 0
      mode_summary.three_plus_major = 0
      mode_summary.minor = 0
      mode_summary.patch = 0
      mode_summary.total = results.count
      mode_summary.total_lib_years = meta_data.total_age
      mode_summary.unowned_issues = 0
      mode_summary.total_cvss = meta_data.total_cvss

      results.each do |hash_line|
        line = hash_line[1]

        next if line.major.nil? # For libraries added for completeness of set, the following will all be empty

        if line.major.positive?
          mode_summary.one_major = mode_summary.one_major + 1 if line.major == 1
          mode_summary.two_major = mode_summary.two_major + 1 if line.major == 2
          mode_summary.three_plus_major = mode_summary.three_plus_major + 1 if line.major > 2
        elsif line.minor.positive?
          mode_summary.minor = mode_summary.minor + 1
        elsif line.patch.positive?
          mode_summary.patch = mode_summary.patch + 1
        end

        mode_summary.unowned_issues = mode_summary.unowned_issues + 1 if line.owner == :attention_needed
      end

      mode_summary.one_number = one_number(mode_summary)

      return mode_summary
    end

    def notify(results)
      recent_time = Time.now - 25 * 60 * 60

      results.each do |hash_line|
        line = hash_line[1]
        if !line.dependabot_created_at.nil? && line.dependabot_created_at > recent_time
          message = ":warning: NEW Dependabot alert! :warning:\n\nPackage: #{hash_line[0]}\n#{line.vulnerabilities}\n\nOwned by #{line.owner}\n#{line.dependabot_permalink}"
          SlackNotify.notify(message)
        end
      end
    end

    def mode_results_specific(mode_results, source)
      {
        one_major: mode_results.dig(source, :one_major),
        two_major: mode_results.dig(source, :two_major),
        three_plus_major: mode_results.dig(source, :three_plus_major),
        minor: mode_results.dig(source, :minor),
        unowned_issues: mode_results.dig(source, :unowned_issues),
        one_number: mode_results.dig(source, :one_number),
      }
    end

    def print_summary(source, meta_data, mode_data)
      puts "#{source}: #{meta_data}, #{mode_data}" if LibraryVersionAnalysis.dev_output?
    end
  end
end
