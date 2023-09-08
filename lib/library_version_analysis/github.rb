require "graphql/client"
require "graphql/client/http"

module LibraryVersionAnalysis
  class Github
    URL = "https://api.github.com/graphql".freeze

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
        createdAt
      }
      pageInfo {
        endCursor
        hasNextPage
      }
    }
    GRAPHQL

    def initialize
      if ENV['GITHUB_READ_API_TOKEN'].nil? || ENV['GITHUB_READ_API_TOKEN'].empty?
        raise "GITHUB_READ_API_TOKEN is not set"
      end

      http_adapter = GraphQL::Client::HTTP.new(URL) do
        def headers(_context)
          {
            "Authorization" => "Bearer #{ENV['GITHUB_READ_API_TOKEN']}",
            "User-Agent" => "Ruby",
          }
        end
      end

      schema = GraphQL::Client.load_schema(http_adapter)
      @client = GraphQL::Client.new(schema: schema, execute: http_adapter)
      @client.allow_dynamic_queries = true

      @alerts_query = @client.parse <<-GRAPHQL
      query($name: String!) {
        repository(name: $name, owner: "GetJobber") {
          vulnerabilityAlerts(first: 100, states: OPEN) {
            ...data
          }
        }
      }
  
      #{ALERTS_FRAGMENT}
      GRAPHQL

      @alerts_query_next = @client.parse <<-GRAPHQL
      query($name: String!, $cursor: String!) {
        repository(name: $name, owner: "GetJobber") {
          vulnerabilityAlerts(first: 100, states: OPEN, after: $cursor) {
            ...data
          }
        }
      }
      #{ALERTS_FRAGMENT}
      GRAPHQL
    end

    def get_dependabot_findings(parsed_results, meta_data, github_name, ecosystem)
      github = LibraryVersionAnalysis::Github.new
      alerts = github.find_alerts(github_name, ecosystem)

      meta_data.total_cvss = 0

      alerts.each do |_, alert|
        package = alert[:package]
        cvss = "#{alert[:severity]} #{alert[:identifiers]}"
        if parsed_results.has_key?(package)
          parsed_results[package].cvss = cvss
        else
          vv = Versionline.new(
            owner: :unknown,
            major: 0,
            minor: 0,
            patch: 0,
            age: 0,
            cvss: cvss,
          )

          parsed_results[package] = vv
        end

        parsed_results[package].dependabot_created_at = Time.parse(alert[:created_at])
        parsed_results[package].dependabot_permalink = alert[:permalink]

        meta_data.total_cvss = meta_data.total_cvss + 1
      end
    end

    def find_alerts(github_name, ecosystem)
      response = @client.query(@alerts_query, variables: { name: github_name })

      alerts = {}

      if response.errors.any?
        raise QueryExecutionError, response.errors[:data].join(", ")
      else
        end_cursor = add_results(response.data.repository.vulnerability_alerts, alerts, ecosystem)
        until end_cursor.nil?
          response = @client.query(@alerts_query_next, variables: { name: github_name, cursor: end_cursor })
          end_cursor = add_results(response.data.repository.vulnerability_alerts, alerts, ecosystem)
        end
      end

      return alerts
    end

    def add_results(alerts, results, target_ecosystem)
      alerts.nodes.each do |alert|
        database_id = alert.security_vulnerability.advisory.database_id
        ecosystem = alert.security_vulnerability.package.ecosystem

        if ecosystem == target_ecosystem && !results.has_key?(database_id)
          results[database_id] = {
            package: alert.security_vulnerability.package.name,
            identifiers: alert.security_vulnerability.advisory.identifiers.map(&:value),
            severity: alert.security_vulnerability.severity,
            created_at: alert.created_at,
            permalink: alert.security_vulnerability.advisory.permalink
          }
        end
      end

      end_cursor = alerts.page_info.has_next_page ? alerts.page_info.end_cursor : nil
      return end_cursor
    end
  end
end
