require "graphql/client"
require "graphql/client/http"
require "pry-byebug"
require "library_version_analysis/configuration"

module LibraryVersionAnalysis
  class Github
    URL = "https://api.github.com/graphql".freeze

    SOURCES = {
      "npm": "NPM",
      "gemfile": "RUBYGEMS",
    }.freeze

    HTTP_ADAPTER = GraphQL::Client::HTTP.new(URL) do
      def headers(_context)
        {
          "Authorization" => "Bearer #{ENV['GITHUB_READ_API_TOKEN']}",
          "LibUser-Agent" => "Ruby",
        }
      end
    end

    ALERTS_FRAGMENT = <<-GRAPHQL.freeze
    fragment data on RepositoryVulnerabilityAlertConnection {
      totalCount
      nodes {
        securityVulnerability {
          package {
            ecosystem
            name
          }
          advisory {
            databaseId
            identifiers {
              type
              value
            }
            publishedAt
            permalink
          }
          severity
        }
        number
        state
        fixedAt
        dependencyScope
        createdAt
      }
      pageInfo {
        endCursor
        hasNextPage
      }
    }
    GRAPHQL

    def get_dependabot_findings(parsed_results, meta_data, github_name, ecosystem)
      raise "GITHUB_READ_API_TOKEN is not set" if ENV['GITHUB_READ_API_TOKEN'].nil? || ENV['GITHUB_READ_API_TOKEN'].empty?

      ecosystem = ecosystem.split(":").first # TODO: THIS IS TEMPORARY DELETE ME

      github = LibraryVersionAnalysis::Github.new

      alerts = github.find_alerts(github_name, true, SOURCES[ecosystem.to_sym])
      meta_data.total_cvss = alerts.count
      add_alerts_to_parsed_results(parsed_results, alerts)

      get_closed_findings(parsed_results, github_name, ecosystem)
    end

    def get_closed_findings(parsed_results, github_name, ecosystem)
      raise "GITHUB_READ_API_TOKEN is not set" if ENV['GITHUB_READ_API_TOKEN'].nil? || ENV['GITHUB_READ_API_TOKEN'].empty?

      ecosystem = ecosystem.split(":").first # TODO: THIS IS TEMPORARY DELETE ME

      github = LibraryVersionAnalysis::Github.new
      alerts = github.find_alerts(github_name, false, SOURCES[ecosystem.to_sym])
      add_alerts_to_parsed_results(parsed_results, alerts)
    end

    def find_alerts(github_name, only_open, ecosystem) # rubocop:disable Metrics/AbcSize
      schema = GraphQL::Client.load_schema(HTTP_ADAPTER)
      client = GraphQL::Client.new(schema: schema, execute: HTTP_ADAPTER)
      client.allow_dynamic_queries = true

      if only_open
        state_filter = "OPEN"
        earliest_fixed_at = nil
      else
        state_filter = "FIXED"
        earliest_fixed_at = DateTime.now - 14 # This is not running in rails, so we can't use 14.days.
      end

      alerts_query = build_alerts_query(client)
      alerts_query_next = build_alerts_query_next(client)

      response = client.query(alerts_query, variables: { name: github_name, state: state_filter })

      found_alerts = {}

      raise QueryExecutionError, response.errors[:data].join(", ") if response.errors.any?

      end_cursor = add_alerts_working_set(response.data.repository.vulnerability_alerts, found_alerts, earliest_fixed_at, ecosystem)
      until end_cursor.nil?
        response = client.query(alerts_query_next, variables: { name: github_name, state: state_filter, cursor: end_cursor })
        end_cursor = add_alerts_working_set(response.data.repository.vulnerability_alerts, found_alerts, earliest_fixed_at, ecosystem)
      end

      return found_alerts
    end

    def add_alerts_working_set(response_alerts, found_alerts, earliest_target_date, target_ecosystem) # rubocop:disable Metrics/AbcSize
      earliest_fixed_date = nil

      response_alerts.nodes.each do |alert|
        database_id = alert.security_vulnerability.advisory.database_id
        ecosystem = alert.security_vulnerability.package.ecosystem

        if ecosystem == target_ecosystem && !found_alerts.has_key?(database_id)
          found_alerts[database_id] = {
            package: alert.security_vulnerability.package.name,
            identifiers: alert.security_vulnerability.advisory.identifiers.map(&:value),
            severity: alert.security_vulnerability.severity,
            created_at: alert.created_at,
            permalink: alert.security_vulnerability.advisory.permalink,
            source: ecosystem,
            state: alert.state,
            fixed_at: alert.fixed_at,
          }

          unless alert.fixed_at.nil? || earliest_target_date.nil?
            new_date = DateTime.parse(alert.fixed_at)
            earliest_fixed_date = new_date if earliest_fixed_date.nil? || new_date < earliest_fixed_date
          end
        end
      end

      end_cursor = response_alerts.page_info.has_next_page ? response_alerts.page_info.end_cursor : nil
      end_cursor = nil if !earliest_fixed_date.nil? && earliest_fixed_date < earliest_target_date

      return end_cursor
    end

    def add_alerts_to_parsed_results(parsed_results, alerts) # rubocop:disable Metrics:MethodLength
      alerts.each do |_, alert| # rubocop:disable Metrics/BlockLength
        package = alert[:package]
        identifiers = alert[:identifiers]
        vulnerability = Vulnerability.new(
          identifier: identifiers,
          fixed_at: alert[:fixed_at].nil? ? nil : Time.parse(alert[:fixed_at]),
          state: alert[:state],
          permalink: alert[:permalink],
          assigned_severity: alert[:severity]
        )

        if parsed_results.has_key?(package)
          if parsed_results[package].vulnerabilities.nil?
            parsed_results[package].vulnerabilities = [vulnerability]
          else
            parsed_results[package].vulnerabilities << vulnerability
          end
        else
          vv = Versionline.new(
            owner: LibraryVersionAnalysis::Configuration.get(:default_owner_name),
            current_version: "?",
            major: 0,
            minor: 0,
            patch: 0,
            age: 0,
            vulnerabilities: [vulnerability]
          )

          parsed_results[package] = vv
        end
      end
    end

    def build_alerts_query(client)
      client.parse <<-GRAPHQL
      query($name: String!, $state: [RepositoryVulnerabilityAlertState!]) {
        repository(name: $name, owner: "GetJobber") {
          vulnerabilityAlerts(first: 100, states: $state) {
            ...data
          }
        }
      }
      #{ALERTS_FRAGMENT}
      GRAPHQL
    end

    def build_alerts_query_next(client)
      client.parse <<-GRAPHQL
      query($name: String!, $state: [RepositoryVulnerabilityAlertState!], $cursor: String!) {
        repository(name: $name, owner: "GetJobber") {
          vulnerabilityAlerts(first: 100, states: $state, after: $cursor) {
            ...data
          }
        }
      }
      #{ALERTS_FRAGMENT}
      GRAPHQL
    end
  end
end
