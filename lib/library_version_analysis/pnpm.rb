require "library_version_analysis/ownership"
require "library_version_analysis/configuration"
require "pathname"

module LibraryVersionAnalysis
  class Pnpm
    include LibraryVersionAnalysis::Ownership

    def initialize(github_repo)
      @github_repo = github_repo
    end

    # Main entry point for per-workspace analysis
    def get_versions_for_all_workspaces # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      workspaces = discover_workspaces

      if single_package_repo?(workspaces)
        # Backwards compatible: non-workspace repos use "pnpm"
        parsed_results, meta_data = get_versions("pnpm")
        return { "pnpm" => { results: parsed_results, meta_data: meta_data } }
      end

      # Workspace repo: iterate ALL packages including root
      results_by_workspace = {}
      workspaces.each do |workspace|
        workspace_path = workspace["path"]
        workspace_source = source_name_for_workspace(workspace_path)

        puts("\tPNPM analyzing workspace: #{workspace_source}") if LibraryVersionAnalysis.dev_output?
        parsed_results, meta_data = get_versions_for_workspace(workspace_path, workspace_source)
        results_by_workspace[workspace_source] = { results: parsed_results, meta_data: meta_data }
      end

      results_by_workspace
    end

    # Check if this is a non-workspace repo (only root package, no workspaces)
    def single_package_repo?(workspaces)
      workspaces.length == 1 && workspaces[0]["path"] == Dir.pwd
    end

    # Convert workspace path to a meaningful source name
    def source_name_for_workspace(workspace_path)
      relative = Pathname.new(workspace_path).relative_path_from(Dir.pwd).to_s
      relative == "." || relative.empty? ? "root" : relative
    end

    # Analyze a single workspace
    def get_versions_for_workspace(workspace_path, source) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      all_libraries = {}
      puts("\tPNPM [#{source}] adding all libraries") if LibraryVersionAnalysis.dev_output?
      all_libraries = add_all_libraries(workspace_path)

      puts("\tPNPM [#{source}] running libyear") if LibraryVersionAnalysis.dev_output?

      libyear_results = run_libyear_for_workspace(source)
      if libyear_results.nil?
        warn "Running libyear for #{source} produced no results. Exiting"
        exit(-1)
      end

      puts("\tPNPM [#{source}] parsing libyear") if LibraryVersionAnalysis.dev_output?
      parsed_results, meta_data = parse_libyear(libyear_results, all_libraries)

      puts("\tPNPM [#{source}] dependabot") if LibraryVersionAnalysis.dev_output?
      add_dependabot_findings(parsed_results, meta_data, @github_repo, source)

      puts("\tPNPM [#{source}] building dependency graph") if LibraryVersionAnalysis.dev_output?
      add_dependency_graph(parsed_results, workspace_path)

      puts("\tPNPM [#{source}] breaking cycles") if LibraryVersionAnalysis.dev_output?
      break_cycles(parsed_results)

      puts("\tPNPM [#{source}] adding ownerships") if LibraryVersionAnalysis.dev_output?
      add_ownerships(parsed_results, workspace_path)

      puts("PNPM [#{source}] done") if LibraryVersionAnalysis.dev_output?

      return parsed_results, meta_data
    end

    def get_versions(source) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      all_libraries = {}
      puts("\tPNPM adding all libraries") if LibraryVersionAnalysis.dev_output?
      all_libraries = add_all_libraries

      puts("\tPNPM running libyear") if LibraryVersionAnalysis.dev_output?

      libyear_results = run_libyear
      if libyear_results.nil?
        warn "Running libyear produced no results. Exiting"
        exit(-1)
      end

      puts("\tPNPM parsing libyear") if LibraryVersionAnalysis.dev_output?
      parsed_results, meta_data = parse_libyear(libyear_results, all_libraries)

      puts("\tPNPM dependabot") if LibraryVersionAnalysis.dev_output?
      add_dependabot_findings(parsed_results, meta_data, @github_repo, source)

      puts("\tPNPM building dependency graph") if LibraryVersionAnalysis.dev_output?
      add_dependency_graph(parsed_results)

      puts("\tPNPM breaking cycles") if LibraryVersionAnalysis.dev_output?
      break_cycles(parsed_results)

      puts("\tPNPM adding ownerships") if LibraryVersionAnalysis.dev_output?
      add_ownerships(parsed_results)

      puts("PNPM done") if LibraryVersionAnalysis.dev_output?

      return parsed_results, meta_data
    end

    def add_dependabot_findings(parsed_results, meta_data, github_repo, source)
      LibraryVersionAnalysis::Github.new.get_dependabot_findings(parsed_results, meta_data, github_repo, source)
    end

    # used when building dependency graphs for upload
    def add_dependency_graph(parsed_results, workspace_path = nil) # rubocop:disable Metrics/MethodLength
      results = run_pnpm_list(workspace_path)
      if results.nil?
        warn "Skipping dependency graph: pnpm list failed"
        return {}
      end

      json = JSON.parse(results)

      @visited_nodes = []
      @parent_count = 0
      all_nodes = {}

      # pnpm list --json returns an array for workspaces
      packages = json.is_a?(Array) ? json : [json]

      packages.each do |package|
        all_nodes = build_dependency_graph(all_nodes, package["dependencies"], nil)
      end

      missing_keys = {} # TODO: handle missing keys
      all_nodes.each do |key, graph|
        if parsed_results.has_key?(key)
          parsed_results[key]["dependency_graph"] = graph
        else
          missing_keys[key] = graph
        end
      end

      puts "Created dependency graph for #{@parent_count} libraries" if LibraryVersionAnalysis.dev_output?

      return all_nodes
    end

    private

    def run_libyear
      # Ideally, we'd run the "pnpx libyear --package-manager pnpm --all --json" command from here.
      # Works great in dev. On Circle, it gets sigkilled with a 137 error (out-of-memory).
      # As a work-around, run libyear before analyze and then just read the output.

      results_file = "libyear_report.txt"
      results = read_file(results_file, true)

      return results
    end

    # Read per-workspace libyear file generated by CI
    def run_libyear_for_workspace(workspace_source)
      filename = libyear_filename_for_source(workspace_source)
      read_file(filename, true)
    end

    # Convert source name to libyear filename
    # "pnpm" -> "libyear_report.txt" (backwards compatible for non-workspace repos)
    # "root" -> "libyear_root.txt"
    # "apps/anchor" -> "libyear_apps_anchor.txt"
    def libyear_filename_for_source(source)
      case source
      when "pnpm"
        "libyear_report.txt"
      else
        "libyear_#{source.gsub('/', '_')}.txt"
      end
    end

    def read_file(path, check_time)
      # With this file-read approach, we could be using old data. protect against that.
      if !File.exist?(path) || (check_time && Time.now.utc - File.mtime(path) > 3600) # 1 hour
        warn "Either could not find #{File.expand_path(path)} or it is more than 1 hour old."
        warn "Ensure libyear files are generated in CI before running analysis."
        exit(-1)
      end

      return File.read(path)
    end

    def run_libyear_open3
      cmd = "pnpx libyear --package-manager pnpm --all --json"
      results, _captured_err, status = Open3.capture3(cmd)

      return nil if status.exitstatus != 0

      results
    end

    def add_all_libraries(workspace_path = nil) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      all_libraries = {}
      cmd = if workspace_path
              "pnpm list --dir #{workspace_path} --depth=Infinity --silent"
            else
              "pnpm list --depth=Infinity --silent"
            end

      results, _stderr, _status = Open3.capture3(cmd)

      results.each_line do |line|
        next if line.include?("UNMET OPTIONAL DEPENDENCY")

        # pnpm list output format is slightly different from npm
        # Example: ├── lodash 4.17.21
        scan_result = line.scan(/^.*?\s([@\w][^\s]+)\s([.\d]+)/)

        if scan_result.nil? || scan_result.empty?
          # Try alternative format: ├── @scope/package@version
          scan_result = line.scan(/^.*?\s([@\w].+)@([.\d]+)/)
        end

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
        owner: LibraryVersionAnalysis::Configuration.get(:default_owner_name),
        current_version: current_version,
        current_version_date: "",
        latest_version_date: ""
      )
    end

    def parse_libyear(results, all_libraries) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
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

    def add_ownerships(parsed_results, workspace_path = nil)
      if workspace_path
        # Per-workspace mode: only read ownerships from that workspace's package.json
        pkg_json_path = File.join(workspace_path, "package.json")
        workspace_ownerships = read_package_json_ownerships(pkg_json_path)

        # Apply workspace ownerships directly
        parsed_results.each do |name, line_data|
          owner = workspace_ownerships[name]
          if owner
            line_data.owner = owner
            line_data.owner_reason = LibraryVersionAnalysis::Ownership::OWNER_REASON_ASSIGNED
          end
        end
      else
        # Legacy mode: cascading ownership across all workspaces
        # 1. Collect all ownership definitions with cascading support
        root_ownerships = read_package_json_ownerships("package.json")
        workspace_ownerships = collect_workspace_ownerships

        # 2. Apply ownerships with precedence (workspace > root > default)
        apply_cascading_ownerships(parsed_results, root_ownerships, workspace_ownerships)
      end

      # 3. Second pass for transitive ownership
      add_transitive_ownerships(parsed_results)

      # 4. Third pass for attention needed
      add_attention_needed(parsed_results)
    end

    def read_package_json_ownerships(path)
      return {} unless File.exist?(path)

      file_contents = File.read(path)
      package_data = JSON.parse(file_contents)
      package_data["ownerships"] || {}
    rescue JSON::ParserError
      {}
    end

    def collect_workspace_ownerships
      workspaces = discover_workspaces
      ownerships = {}

      workspaces.each do |ws|
        pkg_json_path = File.join(ws["path"], "package.json")
        next unless File.exist?(pkg_json_path)

        ws_ownerships = read_package_json_ownerships(pkg_json_path)
        ownerships[ws["name"]] = ws_ownerships unless ws_ownerships.empty?
      end

      ownerships
    end

    def discover_workspaces
      # Use pnpm list to discover all workspaces
      cmd = "pnpm list -r --depth=-1 --json"
      results, _stderr, status = Open3.capture3(cmd)

      return [] unless status.exitstatus.zero?

      json = JSON.parse(results)
      # pnpm returns an array of workspace packages
      json.is_a?(Array) ? json : [json]
    rescue JSON::ParserError
      []
    end

    def apply_cascading_ownerships(parsed_results, root_ownerships, workspace_ownerships)
      # Build a map of which workspace depends on which library
      library_to_workspace = build_library_workspace_map

      parsed_results.each do |name, line_data|
        owner = nil

        # First check workspace-level ownerships (highest precedence)
        workspace_name = library_to_workspace[name]
        if workspace_name && workspace_ownerships[workspace_name]
          owner = workspace_ownerships[workspace_name][name]
        end

        # Fall back to root ownerships if no workspace-level ownership
        owner ||= root_ownerships[name]

        # Apply owner if found
        if owner
          line_data.owner = owner
          line_data.owner_reason = LibraryVersionAnalysis::Ownership::OWNER_REASON_ASSIGNED
        end
      end
    end

    def build_library_workspace_map
      # Map library names to their primary workspace
      # This helps determine which workspace's ownerships to check first
      library_map = {}

      results = run_pnpm_list_recursive
      return library_map if results.nil?

      begin
        json = JSON.parse(results)
        packages = json.is_a?(Array) ? json : [json]

        packages.each do |package|
          workspace_name = package["name"]
          next if workspace_name.nil?

          collect_dependencies_for_workspace(package["dependencies"], workspace_name, library_map)
        end
      rescue JSON::ParserError
        # Return empty map on parse error
      end

      library_map
    end

    def collect_dependencies_for_workspace(dependencies, workspace_name, library_map)
      return if dependencies.nil?

      dependencies.each do |name, _dep_info|
        # Only assign if not already assigned (first workspace wins)
        library_map[name] ||= workspace_name
      end
    end

    def run_pnpm_list_recursive
      cmd = "pnpm list -r --json --depth=0"
      results, _stderr, status = Open3.capture3(cmd)

      return nil unless status.exitstatus.zero?

      results
    end

    def calculate_version(current_version, new_version)
      return "" if current_version.nil? || current_version.empty?

      left, right = current_version.split("..")
      if right.nil?
        if left == new_version # rubocop:disable Style/GuardClause
          return current_version
        else
          right = left
        end
      end

      if new_version < left # rubocop:disable Style/GuardClause
        return "#{new_version}..#{right}"
      elsif new_version > right
        return "#{left}..#{new_version}"
      else
        return current_version
      end
    end

    # Recursive method used when building dependency graph for upload
    def build_dependency_graph(all_nodes, new_nodes, parents, depth = 0) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      return all_nodes if new_nodes.nil?

      new_nodes.keys.each do |name|
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
        puts "\t\tCycle detected: #{node.name}" if LibraryVersionAnalysis.dev_output?
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

    def run_pnpm_list(workspace_path = nil)
      cmd = if workspace_path
              "pnpm list --dir #{workspace_path} --json --depth=Infinity --silent"
            else
              "pnpm list --json --depth=Infinity --silent"
            end

      results, _stderr, status = Open3.capture3(cmd)

      return nil if status.exitstatus != 0

      results
    end
  end
end
