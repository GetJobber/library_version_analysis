require "googleauth"
require "google/apis/sheets_v4"
require "open3"
require "pry"
require "uri"
require "net/https"

module LibraryVersionAnalysis
  Versionline = Struct.new(
    :owner,
    :parent,
    :current_version,
    :current_version_date,
    :latest_version,
    :latest_version_date,
    :cvss,
    :major,
    :minor,
    :patch,
    :age,
    :source,
    :dependency_graph,
    :dependabot_created_at,
    :dependabot_permalink,
    keyword_init: true
  )
  MetaData = Struct.new(:total_age, :total_releases, :total_major, :total_minor, :total_patch, :total_cvss)
  ModeSummary = Struct.new(:one_major, :two_major, :three_plus_major, :minor, :patch, :total, :total_lib_years, :total_cvss, :unowned_issues, :one_number)

  LibNode = Struct.new(
    :name,
    :parents,
    keyword_init: true
  ) do |new_class|
    def deep_to_h
      h = {}
      h[:name] = name
      h[:parents] = parents&.map(&:deep_to_h)
      h
    end
  end

  DEV_OUTPUT = true

  class CheckVersionStatus
    def self.run(repository:)
      c = CheckVersionStatus.new
      mode_results = c.go(repository: repository)

      return c.build_mode_results(mode_results)
    end

    def go(repository:)
      puts "Check Version" if DEV_OUTPUT

      # TODO: once we fully parameterize this, these go away
      online = false
      online_node = true
      # online = true
      # online_node = false
      mobile = false

      meta_data_online_node, mode_online_node = go_online_node(repository) if online_node
      meta_data_online, mode_online = go_online(repository) if online
      meta_data_mobile, mode_mobile = go_mobile(repository) if mobile

      print_summary("online", meta_data_online, mode_online) if online && DEV_OUTPUT
      print_summary("online_node", meta_data_online_node, mode_online_node) if online_node && DEV_OUTPUT
      print_summary("mobile", meta_data_mobile, mode_mobile) if mobile && DEV_OUTPUT

      puts "Done" if DEV_OUTPUT

      return {
        online: mode_online,
        online_node: mode_online_node,
        mobile: mode_mobile,
      }
    end

    def go_online(repository)
      puts "  online" if DEV_OUTPUT
      online = Online.new("Jobber")
      meta_data_online, mode_online = get_version_summary(online, "OnlineVersionData!A:Q", repository, "ONLINE")

      return meta_data_online, mode_online
    end

    def go_online_node(spreadsheet_id)
      puts "  online node" if DEV_OUTPUT
      mobile_node = Npm.new("Jobber")
      meta_data_online_node, mode_online_node = get_version_summary(mobile_node, "OnlineNodeVersionData!A:Q", spreadsheet_id, "ONLINE NODE")

      return meta_data_online_node, mode_online_node
    end

    def go_mobile(spreadsheet_id)
      puts "  mobile" if DEV_OUTPUT
      mobile = Npm.new("Jobber-mobile")
      meta_data_mobile, mode_mobile = get_version_summary(mobile, "MobileVersionData!A:Q", spreadsheet_id, "MOBILE")

      return meta_data_mobile, mode_mobile
    end

    def get_version_summary(parser, range, repository, source)
      parsed_results, meta_data = parser.get_versions

      mode = get_mode_summary(parsed_results, meta_data)
      data = server_data(parsed_results, repository)

      puts "    updating server" if DEV_OUTPUT
      update_server(data)

      puts "    slack notify" if DEV_OUTPUT
      notify(parsed_results)

      return meta_data, mode
    end

    # represents a single number summary of the state of the libraries
    def one_number(mode_summary)
      return mode_summary.three_plus_major * 50 + mode_summary.two_major * 20 + mode_summary.one_major * 10 + mode_summary.minor + mode_summary.patch * 0.5
    end

    def server_data(results, repository)
      libraries = []
      new_versions = []
      vulns = []
      dependencies = []

      missing_dependency_keys = [] # TODO: handle missing keys
      results.each do |name, row|
        libraries.push({name: name, owner: row.owner, version: row.current_version, source: row.source})
        unless row.cvss.nil? || row.cvss == ""
          vulns.push({library: name, identifier: row.cvss.split("[")[1].delete("]"), assigned_severity: row.cvss.split("[")[0].strip, url: row.dependabot_permalink})
        end
        new_versions.push({name: name, version: row.latest_version, major: row.major, minor: row.minor, patch: row.patch})
        if row.dependency_graph.nil?
          missing_dependency_keys.push(name)
        else
          dependencies.push(row.dependency_graph.deep_to_h)
        end
      end

      binding.pry

      {
        repository: repository,
        libraries: libraries,
        new_versions: new_versions,
        vulnerabilities: vulns,
        dependencies: dependencies,
      }
    end

    def update_server(data)
      uri = URI('http://127.0.0.1:4000/api/libraries/upload')
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
      req["X-Upload-Key"] = ENV["UPLOAD_KEY"]
      req.body = data.to_json
      res = http.request(req)
      puts "response #{res.body}"
    end

    # def spreadsheet_data(results, source)
    #   header_row = %w(name owner parent source current_version current_version_date latest_version latest_version_date major minor patch age cve note cve_label cve_severity note_lookup_key)
    #   data = [header_row]
    #
    #   data << ["Updated: #{Time.now.utc}"]z
    #
    #   results.each do |name, row|
    #     data << [
    #       name,
    #       row.owner,
    #       row.parent,
    #       source,
    #       row.current_version,
    #       row.current_version_date,
    #       row.latest_version,
    #       row.latest_version_date,
    #       row.major,
    #       row.minor,
    #       row.patch,
    #       row.age,
    #       row.cvss,
    #       '=IFERROR(concatenate(vlookup(indirect("Q" & row()),Notes!A:E,4,false), ":", concatenate(vlookup(indirect("Q" & row()),Notes!A:E,5,false))))',
    #       '=IFERROR(vlookup(indirect("Q" & row()),Notes!A:E,4,false), IFERROR(trim(LEFT(INDIRECT("Q" & row()), SEARCH("[", INDIRECT("M" & row()))-1))))',
    #       '=IFERROR(vlookup(indirect("O" & row()),\'Lookup data\'!$A$2:$B$6,2,false))',
    #       '=IF(ISBLANK(indirect("M" & row())), indirect("A" & row()), indirect("M" & row()))'
    #     ]
    #   end
    #
    #   return data
    # end

    # def update_spreadsheet(spreadsheet_id, range_name, results)
    #   service = Google::Apis::SheetsV4::SheetsService.new
    #   service.authorization = ::Google::Auth::ServiceAccountCredentials.make_creds(scope: "https://www.googleapis.com/auth/spreadsheets")
    #
    #   clear_range = Google::Apis::SheetsV4::BatchClearValuesRequest.new
    #   clear_range.ranges = [range_name]
    #   service.batch_clear_values(spreadsheet_id, clear_range)
    #
    #   value_range_object = Google::Apis::SheetsV4::ValueRange.new(range: range_name, values: results)
    #   service.update_spreadsheet_value(spreadsheet_id, range_name, value_range_object, value_input_option: "USER_ENTERED")
    # end
    # end

    def get_mode_summary(results, meta_data)
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

        if unowned_needs_attention?(line)
          mode_summary.unowned_issues = mode_summary.unowned_issues + 1
          line.owner = ":attention_needed"
        end
      end

      mode_summary.one_number = one_number(mode_summary)

      return mode_summary
    end

    def notify(results)
      recent_time = Time.now - 25 * 60 * 60

      # SlackNotify.notify("Don't panic. Just testing, to make slack alerts from lib analysis still happen", "security-alerts")

      results.each do |hash_line|
        line = hash_line[1]
        if (!line.dependabot_created_at.nil? && line.dependabot_created_at > recent_time )
          message = ":warning: NEW Dependabot alert! :warning:\n\nPackage: #{hash_line[0]}\n#{line.cvss}\n\nOwned by #{line.owner}\n#{line.dependabot_permalink}"
          SlackNotify.notify(message, "security-alerts")
        end
      end
    end

    def unowned_needs_attention?(line)
      return false unless line.owner == :unspecified || line.owner == :transitive_unspecified || line.owner == :unknown

      return true if line.major.positive?
      return true if line.major.zero? && line.minor > 20
      return true if !line.age.nil? && line.age > 3.0
      return true unless line.cvss.nil?
    end

    def build_mode_results(mode_results)
      results = {}
      results[:online] = mode_results_specific(mode_results, :online) unless mode_results[:online].nil?
      results[:online_node] = mode_results_specific(mode_results, :online_node) unless mode_results[:online_node].nil?
      results[:mobile] = mode_results_specific(mode_results, :mobile) unless mode_results[:mobile].nil?

      return results
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
      puts "#{source}: #{meta_data}, #{mode_data}"
    end
  end
end
