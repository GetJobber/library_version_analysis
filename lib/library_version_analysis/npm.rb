module LibraryVersionAnalysis
  class Npm
    def initialize(github_repo)
      @github_repo = github_repo
    end

    def get_versions
      puts("Mobile running libyear")

      libyear_results = run_libyear
      if libyear_results.nil?
        warn "Running libyear produced no results. Exiting"
        exit -1
      end

      puts("\tMobile parsing libyear")
      parsed_results, meta_data = parse_libyear(libyear_results)

      puts("\tMobile dependabot")
      LibraryVersionAnalysis::Github.new.get_dependabot_findings(parsed_results, meta_data, @github_repo, "NPM")

      unless LibraryVersionAnalysis::LEGACY_DB_SYNC
        puts("\tMobile adding remaining libraries")
        add_remaining_libraries(parsed_results)
      end

      puts("\tMobile building dependency graph")
      add_dependency_graph( parsed_results)

      puts("\tMobile adding ownerships")
      add_ownerships(parsed_results)

      puts("Mobile done")
      return parsed_results, meta_data
    end

    def add_dependency_graph(parsed_results)
      nodes = Hash.new

      results = run_npm_list
      json = JSON.parse(results)

      nodes = build_dependency_graph(json["dependencies"], nil)

      missing_keys = {} # TODO: handle missing keys
      nodes.each do |key, graph|
        if parsed_results.has_key?(key)
          parsed_results[key]["dependency_graph"] = graph
        else
          missing_keys[key] = graph
        end
      end

      return nodes
    end

    private

    def run_libyear
      # Ideally, we'd run the "npx libyear --json" command from here and capture the results with Open3.
      # Works great in dev. On Circle, it gets sigkilled with a 137 error. That usually means
      # out-of-memory, but I have a suspicion in this case it is exceeding the open pipe limit.
      # The JS version of libyear spawns a node instance for every library.
      #
      # As a work-around, updated circleCi config to run libyear before analyze and then just read the output (JZ)

      # Get libyear results
      results_file = "libyear_report.txt"

      results = read_file(results_file, true)

      return results
    end

    def read_file(path, check_time)
      # With this new file-read approach, we could be using old data. protect against that.
      if !File.exist?(path) || (check_time && Time.now.utc - File.mtime(path) > 600) # 10 minutes
        warn "Either could not find #{File.expand_path(path)} or it is more than 10 minutes old. Run \"npx libyear --json > libyear_report.txt\""
        exit -1
      end

      return File.read(path)
    end

    def run_libyear_open3
      cmd = "npx libyear --json"
      results, captured_err, status = Open3.capture3(cmd)

      if status.exitstatus != 0
        warn "mobile status: #{status}"
        warn "mobile captured_err: #{captured_err}"

        return nil
      end

      return results
    end

    def add_remaining_libraries(parsed_results)
      cmd = "npm list --all"

      results, captured_err, status = Open3.capture3(cmd)
      # ignore errors for this. It actually will fail, but we hopefully don't care

      results.each_line do |line|
        scan_result = line.scan(/^.*?\s([@\w].+)@([.\d]*)/)

        unless scan_result.nil? || scan_result.empty?
          name = scan_result[0][0]

          next if parsed_results.key?(name)

          vv = Versionline.new(
            owner: :unknown,
            current_version: scan_result[0][1],
            source: "npm"
          )

          parsed_results[name] = vv
        end
      end
    end

    def parse_libyear(results)
      all_versions = {}
      data = JSON.parse(results)

      meta_data = create_blank_metadata

      data.each do |line|
        drift = find_drift(line).round(1)
        meta_data.total_age += drift
        meta_data.total_major += line["major"]
        meta_data.total_minor += line["minor"]
        meta_data.total_patch += line["patch"]

        vv = Versionline.new(
          owner: :unknown,
          current_version: "",
          current_version_date: "",
          latest_version: line["available"],
          latest_version_date: "",
          major: line["major"],
          minor: line["minor"],
          patch: line["patch"],
          age: drift,
          source: "npm"
        )

        all_versions[line["dependency"]] = vv
      end

      meta_data.total_age = meta_data.total_age.round(1)
      meta_data.total_releases = data.count

      return all_versions, meta_data
    end

    def create_blank_metadata
      meta_data = MetaData.new
      meta_data.total_age = 0
      meta_data.total_major = 0
      meta_data.total_minor = 0
      meta_data.total_patch = 0
      meta_data
    end

    def find_drift(line)
      drift = line["drift"]
      if drift.nil?
        drift = 0
      else
        drift = drift.round(2)
      end
      drift
    end

    def add_ownerships(parsed_results)
      # Get ownerships
      add_package_json_ownerships(parsed_results)

      # 2nd pass for transitive ownership
      add_transitive_ownerships(parsed_results)
    end

    def add_transitive_ownerships(parsed_results)
      transitive_mappings = build_transitive_mapping(parsed_results)

      parsed_results.select { |_, result_data| result_data.owner == :unknown }.each do |name, line_data|
        parent = transitive_mappings[name]

        next if parent.nil?

        if parsed_results[parent].owner == :unknown
          line_data.owner = :transitive_unspecified # note, this order is important, line_data and parsed_result[parent] could be the same thing
          parsed_results[parent].owner = :unspecified # in which case, we want :unspecified
        else
          line_data.owner = parsed_results[parent].owner
          line_data.parent = parent
        end
      end
    end

    def add_package_json_ownerships(parsed_results)
      package_file = "package.json"
      file = read_file(package_file, false)
      ownerships = {}
      package_data = JSON.parse(file)
      package_data["ownerships"].each do |name, owner|
        ownerships[name] = owner
        parsed_results[name].owner = owner if parsed_results.has_key?(name)
      end
    end

    def build_dependency_graph(npm_nodes, parents)
      return {} if npm_nodes.nil?

      nodes = {}
      npm_nodes.keys.each do |name|
        parent = LibNode.new(name: name, parents: parents.nil? ? nil : [parents])
        nodes[name] = parent
        new_nodes = build_dependency_graph(npm_nodes[name]["dependencies"], parent)
        nodes.merge!(new_nodes)
      end

      return nodes
    end

    def build_transitive_mapping(parsed_results)
      mappings = {}
      results = run_npm_list
      # results <<~EOR
      #   jobber@1.0.0 /Users/johnz/source/Jobber
      #   ├─┬ @amplitude/analytics-browser@1.10.3
      #   │ ├─┬ @amplitude/analytics-client-common@0.7.0
      #   │ │ ├── @amplitude/analytics-connector@1.4.8
      #   │ │ ├── @amplitude/analytics-core@0.13.3 deduped
      #   │ │ ├── @amplitude/analytics-types@0.20.0 deduped
      #   │ │ └── tslib@2.5.0
      # EOR

      # ├ ─ ┬    │ ├ ─ ─   │ │ └ ─ ─ These are the symbols used, keep here for now

      parent = "undefined"

      last_parent = false
      results.each_line do |line|
        scan_result = line.scan(/.* (.*)@(.*)/)
        next if scan_result.nil? || scan_result.empty?

        name = scan_result[0][0]

        current_version = scan_result[0][1]
        parsed_results[name].current_version = current_version unless parsed_results[name].nil?

        if line.start_with?("└")
          last_parent = true
          parent = name
        end

        parent = name if !name.nil? && !last_parent && (line.count("│").zero? || line[0] == "├")

        mappings[name] = parent unless name.nil?
      end

      return mappings
    end

    def run_npm_list
      cmd = "npm list --all --json"
      results, captured_err, status = Open3.capture3(cmd)

      if status.exitstatus != 0
        warn "status: #{status}"
        warn "captured_err: #{captured_err}"
      end
      results
    end
  end
end
