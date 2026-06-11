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
    def self.run(repository: "", source: "", context: nil)
      # check for env vars before we do anything
      keys = %w(WORD_LIST_RANDOM_SEED GITHUB_READ_API_TOKEN LIBRARY_UPLOAD_URL UPLOAD_KEY)
      missing_keys = keys.reject { |key| !ENV[key].nil? && !ENV[key].empty? }

      raise "Missing ENV vars: #{missing_keys}" if missing_keys.any?

      c = CheckVersionStatus.new
      mode_results = c.go(repository: repository, source: source, context: context)

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

      # For pnpm, mode_results contains all_modes hash with each workspace's metrics
      if source == "pnpm"
        results = { result_key => c.pnpm_results_all_workspaces(mode_results, mode_key.to_sym) }
      else
        results = { result_key => c.mode_results_specific(mode_results, mode_key.to_sym) }
      end
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

    def go(repository:, source:, context: nil) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      puts "Check Version" if LibraryVersionAnalysis.dev_output?

      case source
      when "npm"
        meta_data, mode = go_npm(repository, source)
      when "gemfile"
        meta_data, mode = go_gemfile(repository, source)
      when "pnpm"
        meta_data, mode = go_pnpm(repository, context)
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

    def go_gemfile(repository, source)
      puts "  gemfile" if LibraryVersionAnalysis.dev_output?
      gemfile = Gemfile.new(repository)

      meta_data, mode = get_version_summary(gemfile, repository, source)

      return meta_data, mode
    end

    def go_npm(repository, source)
      puts "  npm" if LibraryVersionAnalysis.dev_output?
      npm = Npm.new(repository)

      meta_data, mode = get_version_summary(npm, repository, source)

      return meta_data, mode
    end

    def go_pnpm(repository, context = nil) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      puts "  pnpm" if LibraryVersionAnalysis.dev_output?
      pnpm = Pnpm.new(repository)

      # Get results for ALL workspaces (or single repo)
      results_by_workspace = pnpm.get_versions_for_all_workspaces

      # Filter to specific workspace if context provided
      if context
        if results_by_workspace.key?(context)
          results_by_workspace = { context => results_by_workspace[context] }
        else
          available = results_by_workspace.keys.join(", ")
          puts "Workspace '#{context}' not found. Available workspaces: #{available}"
          exit(-1)
        end
      end

      all_modes = {}
      combined_meta_data = nil

      # Upload each workspace separately
      results_by_workspace.each do |workspace_name, data|
        parsed_results = data[:results]
        meta_data = data[:meta_data]
        mode = get_mode_summary(parsed_results, meta_data)

        # Store first workspace's meta_data for print_summary (backwards compatible)
        combined_meta_data ||= meta_data

        all_modes[workspace_name] = mode

        puts "    updating server for #{workspace_name}" if LibraryVersionAnalysis.dev_output?
        # Use workspace_name as the source for pnpm workspaces
        server_payload = server_data(parsed_results, repository, workspace_name)
        log_server_payload(server_payload)
        LibraryTracking.upload(server_payload.to_json)
      end

      puts "All Done! Uploaded #{results_by_workspace.keys.count} workspace(s)" if LibraryVersionAnalysis.dev_output?

      # Return all_modes hash for pnpm (contains all workspace metrics)
      return combined_meta_data, all_modes
    end

    def get_version_summary(parser, repository, source)
      parsed_results, meta_data = parser.get_versions(source)
      mode = get_mode_summary(parsed_results, meta_data)

      puts "    updating server" if LibraryVersionAnalysis.dev_output?
      server_payload = server_data(parsed_results, repository, source)
      log_server_payload(server_payload)
      data = server_payload.to_json
      LibraryTracking.upload(data)

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

        mode_summary.unowned_issues = mode_summary.unowned_issues + 1 if line.owner == :attention_needed || line.owner == :unspecified
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

    # Format pnpm results with all workspaces included
    def pnpm_results_all_workspaces(mode_results, source)
      all_modes = mode_results[source]
      return {} if all_modes.nil?

      result = {}
      all_modes.each do |workspace_name, mode|
        result[workspace_name] = {
          one_major: mode[:one_major],
          two_major: mode[:two_major],
          three_plus_major: mode[:three_plus_major],
          minor: mode[:minor],
          unowned_issues: mode[:unowned_issues],
          one_number: mode[:one_number],
        }
      end
      result
    end

    def print_summary(source, meta_data, mode_data)
      puts "#{source}: #{meta_data}, #{mode_data}" if LibraryVersionAnalysis.dev_output?
    end

    def log_server_payload(payload)
      warn "[upload] Preparing to upload data for #{payload[:repository]}/#{payload[:source]}"
      warn "[upload] Libraries: #{payload[:libraries]&.count || 0}"
      warn "[upload] New versions: #{payload[:new_versions]&.count || 0}"
      warn "[upload] Vulnerabilities: #{payload[:vulnerabilities]&.count || 0}"
      warn "[upload] Dependencies: #{payload[:dependencies]&.count || 0}"

      # Log sample of libraries (first 10)
      if payload[:libraries]&.any?
        warn "[upload] Sample libraries (first 10):"
        payload[:libraries].first(10).each do |lib|
          warn "[upload]   - #{lib[:name]} @ #{lib[:version]} (owner: #{lib[:owner]})"
        end
        warn "[upload]   ... and #{payload[:libraries].count - 10} more" if payload[:libraries].count > 10
      end

      # Log libraries with version updates
      if payload[:new_versions]&.any?
        outdated = payload[:new_versions].select { |v| v[:major]&.positive? }
        warn "[upload] Libraries with major updates: #{outdated.count}"
        outdated.first(5).each do |lib|
          warn "[upload]   - #{lib[:name]}: #{lib[:major]} major, #{lib[:minor]} minor, #{lib[:patch]} patch behind"
        end
      end

      # Log vulnerabilities
      if payload[:vulnerabilities]&.any?
        warn "[upload] Vulnerabilities found:"
        payload[:vulnerabilities].first(10).each do |vuln|
          warn "[upload]   - #{vuln[:library]}: #{vuln[:assigned_severity]} (#{vuln[:state]})"
        end
      end
    end
  end
end
