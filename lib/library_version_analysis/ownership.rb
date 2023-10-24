module LibraryVersionAnalysis
  module Ownership
    def add_transitive_ownerships(parsed_results)
      parsed_results.select { |_, result_data| unknown_owner?(result_data.owner) }.each do |name, line_data|
        @current_library = name
        owner = find_owner(line_data.dependency_graph, parsed_results)
        line_data.owner = unknown_owner?(owner) ? :unknown : owner
      end
    end

    def find_owner(dependency_graph, parsed_results)
      return nil if dependency_graph.nil?

      owner = parsed_results[dependency_graph.name]&.owner
      return owner unless unknown_owner?(owner)

      parent_owner = nil

      dependency_graph.parents&.each do |parent|
        parent_owner = parsed_results[parent.name]&.owner
        return parent_owner unless unknown_owner?(parent_owner)

        parent_owner = find_owner(parent, parsed_results)
        is_unknown = unknown_owner?(parent_owner)
        break unless is_unknown
      end

      return parent_owner
    end

    def unknown_owner?(owner)
      owner.nil? || owner == "" || owner == :unknown || owner == :attention_needed || owner == :transitive_unspecified || owner == :unspecified
    end
  end
end