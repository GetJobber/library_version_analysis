module LibraryVersionAnalysis
  class Online
    def get_versions
      libyear_results = run_libyear("--versions")

      if libyear_results.nil?
        warn "Running libyear --versions produced no results. Exiting"
        exit(-1)
      end

      parsed_results, meta_data = parse_libyear_versions(libyear_results)
      LibraryVersionAnalysis::Github.new.get_dependabot_findings(parsed_results, meta_data, "Jobber", "RUBYGEMS")

      libyear_results = run_libyear("--libyear")
      unless libyear_results.nil?
        parsed_results, meta_data = parse_libyear_libyear(libyear_results, parsed_results, meta_data)
        add_ownerships(parsed_results)
      end

      return parsed_results, meta_data
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

    def parse_libyear_versions(results)
      all_versions = {}
      meta_data = MetaData.new

      results.each_line do |line|
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

    def parse_libyear_libyear(results, parsed_results, meta_data)
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
      up_to_date_ownership = add_ownership_from_gemfile(parsed_results)
      add_special_case_ownerships(parsed_results)
      add_ownership_from_transitive(parsed_results, up_to_date_ownership)
    end

    def add_ownership_from_gemfile(parsed_results)
      data = read_file

      up_to_date_ownership = {}

      data.each_line do |line|
        scan_result = line.scan(/\s*jgem\s*(\S*),\s*"(\S*)"/)

        next if scan_result.nil? || scan_result.empty?

        owner = scan_result[0][0]
        gem = scan_result[0][1]

        version = parsed_results[gem]
        if version.nil?
          up_to_date_ownership[gem] = owner
          next
        end

        version.owner = owner
      end

      return up_to_date_ownership
    end

    def read_file
      file = File.open("./Gemfile")
      data = file.read
      file.close

      return data
    end

    def add_ownership_from_transitive(parsed_results, up_to_date_ownership)
      parsed_results.select { |_, result_data| result_data.owner == :unknown }.each do |name, line_data|
        cmd = "bundle why #{name}"
        results, captured_err, status = Open3.capture3(cmd)

        if status.exitstatus != 0
          warn "status: #{status}"
          warn "captured_err: #{captured_err}"
        end

        if results.include?("->")
          scan_result = results.scan(/(.*?) -> .*/)

          next if scan_result.nil? || scan_result.empty?

          parent_name = scan_result[0][0]

          if parsed_results[parent_name].nil? && up_to_date_ownership.has_key?(parent_name)
            line_data.owner = up_to_date_ownership[parent_name]
            line_data.parent = parent_name
          elsif parsed_results[parent_name].nil? || parsed_results[parent_name].owner == :unknown || parsed_results[parent_name].owner == :unspecified
            line_data.owner = :transitive_unspecified
          else
            parent_owner = parsed_results[parent_name].owner
            line_data.owner = parent_owner
            line_data.parent = parent_name
          end
        else
          line_data.owner = :unspecified
        end
      end
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
          parsed_results[name.to_s].owner = owner if parsed_results.has_key?(name.to_s)
          parsed_results[name.to_s].parent = "Rails"
        else
          parsed_results[name.to_s] = Versionline.new(owner: owner, major: 0, minor: 0, patch: 0)
        end
      end
    end
  end
end
