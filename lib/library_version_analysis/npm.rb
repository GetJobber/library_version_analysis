module LibraryVersionAnalysis
  class Npm
    def initialize(github_repo)
      @github_repo = github_repo
    end

    def get_versions
      all_libraries = {}
      unless LibraryVersionAnalysis::CheckVersionStatus.legacy?
        puts("\tNPM adding all libraries") if LibraryVersionAnalysis::DEV_OUTPUT
        all_libraries = add_all_libraries
      end

      puts("\tNPM running libyear") if LibraryVersionAnalysis::DEV_OUTPUT

      libyear_results = run_libyear
      if libyear_results.nil?
        warn "Running libyear produced no results. Exiting"
        exit -1
      end

      puts("\tNPM parsing libyear") if LibraryVersionAnalysis::DEV_OUTPUT
      parsed_results, meta_data = parse_libyear(libyear_results, all_libraries)

      puts("\tNPM dependabot") if LibraryVersionAnalysis::DEV_OUTPUT
      add_dependabot_findings(parsed_results, meta_data, @github_repo)

      unless LibraryVersionAnalysis::CheckVersionStatus.legacy?
        puts("\tNPM building dependency graph") if LibraryVersionAnalysis::DEV_OUTPUT
        add_dependency_graph(parsed_results)

        puts("\tNPM breaking cycles") if LibraryVersionAnalysis::DEV_OUTPUT
        break_cycles(parsed_results)
      end

      puts("\tNPM adding ownerships") if LibraryVersionAnalysis::DEV_OUTPUT
      add_ownerships(parsed_results)

      puts("NPM done") if LibraryVersionAnalysis::DEV_OUTPUT
      return parsed_results, meta_data
    end

    def add_dependabot_findings(parsed_results, meta_data, github_repo)
      LibraryVersionAnalysis::Github.new.get_dependabot_findings(parsed_results, meta_data, github_repo, "NPM")
    end

    # used when building dependency graphs for upload
    def add_dependency_graph(parsed_results)
      results = run_npm_list
      json = JSON.parse(results)

      @visited_nodes = []
      @parent_count = 0
      all_nodes = {}
      all_nodes = build_dependency_graph(all_nodes, json["dependencies"], nil)
      missing_keys = {} # TODO: handle missing keys
      all_nodes.each do |key, graph|
        if parsed_results.has_key?(key)
          parsed_results[key]["dependency_graph"] = graph
        else
          missing_keys[key] = graph
        end
      end

      puts "Created dependency graph for #{@parent_count} libraries"

      return all_nodes
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

    def add_all_libraries
      all_libraries = {}
      cmd = "npm list --all --silent"

      # ignore errors for this. It actually will fail, but we hopefully don't care
      results, captured_err, status = Open3.capture3(cmd)

      results.each_line do |line|
        next if line.include?("UNMET OPTIONAL DEPENDENCY")

        scan_result = line.scan(/^.*?\s([@\w].+)@([.\d]*)/)

        unless scan_result.nil? || scan_result.empty?
          name = scan_result[0][0]

          vv = all_libraries[name]
          if vv.nil?
            vv = new_version_line(scan_result[0][1])
            all_libraries[name] = vv
          else
            vv.current_version = calculate_version(vv.current_version, scan_result[0][1])
          end
        end
      end

      return all_libraries
    end

    def new_version_line(current_version)
      Versionline.new(
        owner: :unknown,
        current_version: current_version,
        current_version_date: "",
        latest_version_date: "",
        source: "npm"
      )
    end

    def parse_libyear(results, all_libraries)
      data = JSON.parse(results)

      meta_data = create_blank_metadata

      data.each do |line|
        drift = find_drift(line).round(1)
        meta_data.total_age += drift
        meta_data.total_major += line["major"]
        meta_data.total_minor += line["minor"]
        meta_data.total_patch += line["patch"]

        vv = all_libraries[line["dependency"]]
        if vv.nil?
          vv = new_version_line("")
          all_libraries[line["dependency"]] = vv
        end

        vv.latest_version = line["available"]
        vv.major = line["major"]
        vv.minor = line["minor"]
        vv.patch = line["patch"]
        vv.age = drift
      end

      meta_data.total_age = meta_data.total_age.round(1)
      meta_data.total_releases = data.count

      return all_libraries, meta_data
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
      if LibraryVersionAnalysis::CheckVersionStatus.legacy?
        add_transitive_ownerships_legacy(parsed_results)
      else
        add_transitive_ownerships(parsed_results)
      end
    end

    def add_transitive_ownerships(parsed_results)
      parsed_results.select { |_, result_data| LibraryVersionAnalysis::CheckVersionStatus.unknown_owner?(result_data.owner) }.each do |name, line_data|
        @current_library = name
        owner = find_owner(line_data.dependency_graph, parsed_results)
        line_data.owner = LibraryVersionAnalysis::CheckVersionStatus.unknown_owner?(owner) ? :unknown : owner
      end
    end

    def find_owner(dependency_graph, parsed_results)
      return nil if dependency_graph.nil?

      owner = parsed_results[dependency_graph.name]&.owner
      return owner unless LibraryVersionAnalysis::CheckVersionStatus.unknown_owner?(owner)

      parent_owner = nil

      dependency_graph.parents&.each do |parent|
        parent_owner = parsed_results[parent.name]&.owner
        return parent_owner unless LibraryVersionAnalysis::CheckVersionStatus.unknown_owner?(parent_owner)

        parent_owner = find_owner(parent, parsed_results)
        is_unknown = LibraryVersionAnalysis::CheckVersionStatus.unknown_owner?(parent_owner)
        break unless is_unknown
      end

      return parent_owner
    end

    def add_transitive_ownerships_legacy(parsed_results)
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

    def calculate_version(current_version, new_version)
      left, right = current_version.split("..")
      if right.nil?
        if left == new_version
          return current_version
        else
          right = left
        end
      end

      if new_version < left
        return "#{new_version}..#{right}"
      elsif new_version > right
        return "#{left}..#{new_version}"
      else
        return current_version
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

    # Recursive method used when building dependency graph for upload
    def build_dependency_graph(all_nodes, new_nodes, parents, depth=0)
      return all_nodes if new_nodes.nil?

      new_nodes.keys.each do |name|
        # if push_unique(name).nil?
        #   puts "Cycle detected: #{name}"
        #   next
        # end

        parent = all_nodes[name]
        if parent.nil?
          @parent_count += 1
          parent = LibNode.new(name: name, parents: parents.nil? ? nil : [parents])
          all_nodes[name] = parent
        end

        existing_parents = parent.parents
        if existing_parents.nil? && !parents.nil?
          existing_parents = []
          parent.parents = existing_parents
        end

        existing_parents.push(parents) if !parents.nil? && !existing_parents.include?(parents)

        all_nodes = build_dependency_graph(all_nodes, new_nodes[name]["dependencies"], parent, depth + 1)

        @visited_nodes.pop
      end

      return all_nodes
    end

    def push_unique(node)
      return nil if @visited_nodes.include?(node)

      @visited_nodes.push(node)
    end

    def break_cycles(parsed_results)
      # Do a depth first pre-order traversal of the dependency graphs. Keep nodes on stack, if a node
      # is already on the stack, then we have a cycle. Remove the cycle by removing the parent from the
      # dependency graph.
      parsed_results.each do |_, line_data|
        next if line_data["dependency_graph"].nil?

        @visited_nodes = []
        break_cycles_for_graph(line_data["dependency_graph"])
      end
    end

    def break_cycles_for_graph(node)
      return if node.nil?

      if push_unique(node.name).nil?
        puts "\t\tCycle detected: #{node.name}"
        # binding.pry if node.name == "execa"
        return true
      end

      new_parents = []
      node.parents&.each do |parent|
        cycle_found = break_cycles_for_graph(parent)
        new_parents.append(parent) unless cycle_found
      end
      node.parents = new_parents

      @visited_nodes.pop
      return false
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
      if LibraryVersionAnalysis::CheckVersionStatus.legacy?
        cmd = "npm list --silent"
      else
        cmd = "npm list --all --json --silent"
      end
      results, _, status = Open3.capture3(cmd)

      if status.exitstatus != 0
        parsed = JSON.parse(results)
        warn "error while running npm list: #{parsed['error']}"
      end
      results
    end
  end
end
