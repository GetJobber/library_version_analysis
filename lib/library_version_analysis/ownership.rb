module LibraryVersionAnalysis
  module Ownership
    OWNER_REASON_ASSIGNED = "-assigned-".freeze

    def add_transitive_ownerships(parsed_results)
      parsed_results.select { |_, result_data| unknown_owner?(result_data.owner) }.each do |name, line_data|
        @current_library = name

        owner, owner_reason = find_owner(line_data.dependency_graph, parsed_results)
        if unknown_owner?(owner)
          line_data.owner = unknown_owner?(owner) ? :unknown : owner
        else
          line_data.owner = owner
          line_data.owner_reason = owner_reason
        end
      end
    end

    def find_owner(dependency_graph, parsed_results) # rubocop:disable Metrics/AbcSize
      return nil if dependency_graph.nil?

      owner = parsed_results[dependency_graph.name]&.owner
      return owner unless unknown_owner?(owner)

      parent_owner = nil

      dependency_graph.parents&.each do |parent|
        parent_owner = parsed_results[parent.name]&.owner
        parent_owner_reason = parsed_results[parent.name]&.owner_reason
        owner_reason = (parent_owner_reason.nil? || parent_owner_reason == "-assigned-") ? parent.name : parent_owner_reason # rubocop:disable Style/TernaryParentheses
        return parent_owner, owner_reason unless unknown_owner?(parent_owner)

        parent_owner = find_owner(parent, parsed_results)
        is_unknown = unknown_owner?(parent_owner)
        break unless is_unknown
      end

      return parent_owner
    end

    def unknown_owner?(owner)
      owner.nil? || owner == "" || owner == :unknown || owner == :attention_needed || owner == :transitive_unspecified || owner == :unspecified
    end

    def add_attention_needed(parsed_results)
      parsed_results.each do |name, line|
        next if line.vulnerabilities.nil? || line.vulnerabilities.empty?

        line.owner = :attention_needed if unknown_owner?(line.owner)
      end
    end
  end
end
