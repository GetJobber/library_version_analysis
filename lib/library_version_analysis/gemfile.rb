require "library_version_analysis/ownership"

module LibraryVersionAnalysis
  class Gemfile
    include LibraryVersionAnalysis::Ownership

    def initialize(github_repo)
      @github_repo = github_repo
    end

    def get_versions(source) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      puts("\tGemfile running libyear versions") if LibraryVersionAnalysis::DEV_OUTPUT
      libyear_results = run_libyear("--versions")

      if libyear_results.nil?
        warn "Running libyear --versions produced no results. Exiting"
        exit(-1)
      end

      puts("\tGemfile parsing libyear") if LibraryVersionAnalysis::DEV_OUTPUT
      parsed_results, meta_data = parse_libyear_versions(libyear_results)

      puts("\tGemfile dependabot") if LibraryVersionAnalysis::DEV_OUTPUT
      add_dependabot_findings(parsed_results, meta_data, @github_repo, source)

      puts("\tGemfile running libyear libyear") if LibraryVersionAnalysis::DEV_OUTPUT
      libyear_results = run_libyear("--libyear")
      unless libyear_results.nil? # rubocop:disable Style/IfUnlessModifier
        parsed_results, meta_data = parse_libyear_libyear(libyear_results, parsed_results, meta_data)
      end

      unless LibraryVersionAnalysis::CheckVersionStatus.legacy?
        puts("\tGemfile adding remaining libraries") if LibraryVersionAnalysis::DEV_OUTPUT
        add_remaining_libraries(parsed_results)

        puts("\tGemfile building dependency graphs") if LibraryVersionAnalysis::DEV_OUTPUT
        add_dependency_graph(why_init, parsed_results)
      end

      puts("\tGemfile adding ownerships") if LibraryVersionAnalysis::DEV_OUTPUT
      add_ownerships(parsed_results)

      puts("Gemfile done") if LibraryVersionAnalysis::DEV_OUTPUT

      return parsed_results, meta_data
    end

    def add_dependency_graph(spec_set, parsed_results)
      nodes = Hash.new

      spec_set.each do |spec|
        nodes = build_dependency_graph(spec, nodes, spec_set)
      end

      nodes.each do |key, graph|
        parsed_results[key]["dependency_graph"] = graph
      end

      return nodes
    end

    private

    def check_for(regex, line)
      scan_result = line.scan(/#{regex}/)
      return scan_result[0][0] unless scan_result.nil? || scan_result.empty?

      nil
    end

    def run_libyear(param)
      # there is a bug in libyear (which I'm proposing a fix for) that makes -all fail, so
      # we need to run --libyar and --releases separately
      cmd = "libyear-bundler #{param}"
      results, captured_err, status = Open3.capture3(cmd)

      if status.exitstatus != 0
        warn "status: #{status}"
        warn "captured_err: #{captured_err}"

        return nil
      end

      results
    end

    def parse_libyear_versions(results) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      all_versions = {}
      meta_data = MetaData.new

      results.each_line do |line| # rubocop:disable Metrics/BlockLength
        # scan_result = line.scan(/\s*(\S*)\s*(\S*)\s*(\S*)\s*(\S*)\s*(\S*)\s*(\S*)\s*\[(\d*), (\d*), (\d*)\]\s*(\S*)/) KEEP THIS FOR LIBYEAR FIX
        scan_result = line.scan(/\s*(\S*)\s*(\S*)\s*(\S*)\s*(\S*)\s*(\S*)\s*\[(\d*), (\d*), (\d*)\]/)

        if scan_result.nil? || scan_result.empty?
          # check for meta data
          data = check_for("Total releases behind: (.*)", line)
          meta_data.total_releases = data.to_i unless data.nil?

          semver_data = check_for("Major, minor, patch versions behind: (.*)", line)
          unless semver_data.nil?
            split_semver = semver_data.split(",")
            meta_data.total_major = split_semver[0].to_i
            meta_data.total_minor = split_semver[1].to_i
            meta_data.total_patch = split_semver[2].to_i
          end

          next
        end

        scan = scan_result[0]

        next if scan[0] == "ruby" # ruby is special case, but this will mess up meta data slightly. need to figure that out

        vv = Versionline.new(
          owner: :unknown,
          current_version: scan[1],
          current_version_date: scan[2],
          latest_version: scan[3],
          latest_version_date: scan[4],
          major: scan[5].to_i,
          minor: scan[6].to_i,
          patch: scan[7].to_i
        )

        all_versions[scan[0]] = vv
      end

      meta_data.total_releases = all_versions.count

      return all_versions, meta_data
    end

    def add_dependabot_findings(parsed_results, meta_data, github_repo, source)
      LibraryVersionAnalysis::Github.new.get_dependabot_findings(parsed_results, meta_data, github_repo, source)
    end

    def parse_libyear_libyear(results, parsed_results, meta_data) # rubocop:disable Metrics/AbcSize
      results.each_line do |line|
        if line.include?("System is")
          data = check_for("System is (.*) libyears behind", line)
          meta_data.total_age = data.to_f unless data.nil?

          next
        end

        scan_result = line.scan(/\s*(\S*)\s*(\S*)\s*(\S*)\s*(\S*)\s*(\S*)\s*(\S*)/)

        unless scan_result.nil? || scan_result.empty?
          next if scan_result[0][0] == "ruby" # ruby is special

          parsed_results[scan_result[0][0]].age = scan_result[0][5].to_f.round(2)
        end
      end

      return parsed_results, meta_data
    end

    def add_ownerships(parsed_results)
      add_ownership_from_gemfile(parsed_results)
      add_special_case_ownerships(parsed_results)
      add_transitive_ownerships(parsed_results)
    end

    def add_ownership_from_gemfile(parsed_results)
      data = read_file

      data.each_line do |line|
        scan_result = line.scan(/\s*jgem\s*(\S*),\s*"(\S*)"/)

        next if scan_result.nil? || scan_result.empty?

        owner = scan_result[0][0]
        gem = scan_result[0][1]

        version = parsed_results[gem]
        next if version.nil?

        version.owner = owner
        version.owner_reason = LibraryVersionAnalysis::Ownership::OWNER_REASON_ASSIGNED
      end
    end

    def read_file
      file = File.open("./Gemfile")
      data = file.read
      file.close

      return data
    end

    def add_special_case_ownerships(parsed_results)
      special_cases = {
        actioncable: ":api_platform",
        actionmailbox: ":api_platform",
        actionmailer: ":api_platform",
        actionpack: ":api_platform",
        actiontext: ":api_platform",
        actionview: ":api_platform",
        activejob: ":api_platform",
        activemodel: ":api_platform",
        activerecord: ":api_platform",
        activestorage: ":api_platform",
        activesupport: ":api_platform",
        jobber_common_async: ":enablers",
        jobber_common_base: ":enablers",
        jobber_common_dev_setup: ":enablers",
        jobber_common_concerns: ":enablers",
        jobber_common_configuration: ":enablers",
        jobber_monkey_patches: ":enablers",
        jobber_opensearch_client: ":enablers",
        rails: ":api_platform",
        railties: ":api_platform",
      }

      special_cases.each do |name, owner|
        if parsed_results.has_key?(name.to_s)
          parsed_results[name.to_s].owner = owner
          parsed_results[name.to_s].owner_reason = "-assigned-in-code-"
          parsed_results[name.to_s].parent = "Rails"
        else
          parsed_results[name.to_s] = Versionline.new(owner: owner, owner_reason: "-assigned-in-code-", major: 0, minor: 0, patch: 0)
        end
      end
    end

    def add_remaining_libraries(parsed_results)
      results = Bundler.load.specs.sort.map(&:full_name)
      results.each do |line|
        scan_result = line.scan(/(.*)-(.*)/)

        unless scan_result.nil? || scan_result.empty?
          name = scan_result[0][0]

          next if parsed_results.has_key?(name)

          vv = Versionline.new(
            owner: :unknown,
            current_version: scan_result[0][1]
          )

          parsed_results[name] = vv
        end
      end
    end

    # The following comes from https://github.com/jaredbeck/bundler-why/blob/trunk/lib/bundler/why/command.rb, but too
    # slow as written.
    # From 5 minutes to 2 seconds
    def why_init
      runtime = Bundler.load
      spec_set = runtime.specs # delegates to Bundler::Definition#specs

      return spec_set
    end

    def why(gem_name, spec_set)
      spec = find_one_spec_in_set(spec_set, gem_name)

      traverse(spec_set, spec)
    end

    # @param spec_set Bundler::SpecSet
    # @param parent Bundler::StubSpecification
    # @param path Array[Bundler::StubSpecification]
    # @void
    def traverse(spec_set, parent, path = [parent])
      children = spec_set.select do |s|
        s.dependencies.any? do |d|
          d.type == :runtime && d.name == parent.name
        end
      end
      if children.empty? # rubocop:disable Style/GuardClause
        return path
      else
        children.each do |child|
          traverse(spec_set, child, [child].concat(path))
        end
      end
    end

    def find_one_spec_in_set(spec_set, gem_name)
      specs = spec_set[gem_name]
      if specs.length != 1
        warn format(
          'Expected %s to match exactly 1 spec, got %d',
          gem_name, specs.length
        )
      end
      specs.first
    end

    def build_dependency_graph(spec, nodes, spec_set) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      current_node = nodes[spec.name]
      if current_node.nil?
        current_node = LibNode.new(name: spec.name)
        nodes[spec.name] = current_node
      end

      spec.dependencies&.each do |dep|
        dep_node = nodes[dep.name]
        if dep_node.nil?
          dep_node = LibNode.new(name: dep.name)
          nodes[dep.name] = dep_node
        end

        if dep_node.parents.nil?
          dep_node.parents = [current_node]
        else
          dep_node.parents.push(current_node) unless dep_node.parents.include?(current_node)
        end

        child_spec = find_one_spec_in_set(spec_set, dep.name)
        nodes = build_dependency_graph(child_spec, nodes, spec_set)
      end

      return nodes
    end
  end
end
