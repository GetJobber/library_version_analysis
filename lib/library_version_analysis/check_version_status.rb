require "open3"
require "pry"
require "googleauth"
require "google/apis/sheets_v4"

# require "./online"
# require "./mobile"

module LibraryVersionAnalysis
  Versionline = Struct.new(
    :owner,
    :current_version,
    :current_version_date,
    :latest_version,
    :latest_version_date,
    :releases_behind,
    :major,
    :minor,
    :patch,
    :age
  )
  MetaData = Struct.new(:total_age, :total_releases, :total_major, :total_minor, :total_patch)
  ModeSummary = Struct.new(:one_major, :two_major, :three_plus_major, :minor, :total, :total_lib_years, :one_number)

  # Valid owners. Keep for easy reference:
  # :api_platform
  # :core
  # :enablers
  # :fintech
  # :front_end_foundations
  # :production_engineering
  # :self_serve

  class CheckVersionStatus
    # The following warnings point to rails features. This will not be running under rails.
    # rubocop:disable Rails/Output

    # Useful during dev
    # ONLINE_OVERRIDE = true
    # ONLINE_OVERRIDE = false
    # ONLINE_NODE_OVERRIDE = true
    # ONLINE_NODE_OVERRIDE = false
    # MOBILE_OVERRIDE = true
    # MOBILE_OVERRIDE = false

    def self.run(spreadsheet_id:, online: "true", online_node: "true", mobile: "true")
      c = CheckVersionStatus.new
      mode_results = c.go(spreadsheet_id, online == "true", online_node == "true", mobile == "true")

      return c.build_mode_results(mode_results)
    end

    def go(spreadsheet_id, online, online_node, mobile)
      puts "Check Version"

      # useful during dev
      online = ONLINE_OVERRIDE if defined?(ONLINE_OVERRIDE)
      online_node = ONLINE_NODE_OVERRIDE if defined?(ONLINE_NODE_OVERRIDE)
      mobile = MOBILE_OVERRIDE if defined?(MOBILE_OVERRIDE)

      meta_data_online, mode_online = go_online(spreadsheet_id) if online
      meta_data_online_node, mode_online_node = go_online_mode(spreadsheet_id) if online_node
      meta_data_mobile, mode_mobile = go_mobile(spreadsheet_id) if mobile

      print_summary("online", meta_data_online, mode_online) if online
      print_summary("online_node", meta_data_online_node, mode_online_node) if online_node
      print_summary("mobile", meta_data_mobile, mode_mobile) if mobile

      return {
        online: mode_online,
        online_node: mode_online_node,
        mobile: mode_mobile,
      }
    end

    def go_online(spreadsheet_id)
      puts "  online"
      online = Online.new
      meta_data_online, mode_online = get_version_summary(online, "OnlineVersionData!A:L", spreadsheet_id, nil, "ONLINE")

      return meta_data_online, mode_online
    end

    def go_online_mode(spreadsheet_id)
      puts "  online node"
      mobile_node = Mobile.new
      meta_data_online_node, mode_online_node = get_version_summary(mobile_node, "OnlineNodeVersionData!A:L", spreadsheet_id, ".", "ONLINE NODE")

      return meta_data_online_node, mode_online_node
    end

    def go_mobile(spreadsheet_id)
      puts "  mobile"
      mobile = Mobile.new
      meta_data_mobile, mode_mobile = get_version_summary(mobile, "MobileVersionData!A:L", spreadsheet_id, "../jobber-mobile", "MOBILE")

      return meta_data_mobile, mode_mobile
    end

    def get_version_summary(parser, range, spreadsheet_id, path, source)
      parsed_results, meta_data = parser.get_versions(path)
      mode = get_mode_summary(parsed_results, meta_data)
      data = spreadsheet_data(parsed_results, source)

      puts "    updating spreadsheet"
      update_spreadsheet(spreadsheet_id, range, data)

      return meta_data, mode
    end

    # represents a single number summary of the state of the libraries
    def one_number(meta_data)
      return meta_data.total_major.to_i * 100 + meta_data.total_minor.to_i * 10 + meta_data.total_patch.to_i
    end

    def spreadsheet_data(results, source)
      header_row = %w(name owner source current_version current_version_date latest_version latest_version_date releases_behind major minor patch age)
      data = [header_row]

      data << ["Updated: #{Time.now.utc}"]

      results.each do |name, row|
        data << [
          name,
          row.owner,
          source,
          row.current_version,
          row.current_version_date,
          row.latest_version,
          row.latest_version_date,
          row.releases_behind,
          row.major,
          row.minor,
          row.patch,
          row.age,
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
      service.update_spreadsheet_value(spreadsheet_id, range_name, value_range_object, value_input_option: "RAW")
    end

    def get_mode_summary(results, meta_data)
      mode_summary = ModeSummary.new
      mode_summary.one_major = 0
      mode_summary.two_major = 0
      mode_summary.three_plus_major = 0
      mode_summary.minor = 0
      mode_summary.total = results.count
      mode_summary.total_lib_years = meta_data.total_age
      mode_summary.one_number = one_number(meta_data)

      results.each do |hash_line|
        line = hash_line[1]

        if line.major.positive?
          mode_summary.one_major = mode_summary.one_major + 1 if line.major == 1
          mode_summary.two_major = mode_summary.two_major + 1 if line.major == 2
          mode_summary.three_plus_major = mode_summary.three_plus_major + 1 if line.major > 2
        elsif line.minor.positive?
          mode_summary.minor = mode_summary.minor + 1
        end
      end

      return mode_summary
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
        one_number: mode_results.dig(source, :one_number),
      }
    end

    def print_summary(source, meta_data, mode_data)
      puts "#{source}: #{meta_data}, #{mode_data}"
    end

    # rubocop:enable Rails/Output
  end
end