require "graphql/client"
require "graphql/client/http"
require "pry"

module LibraryVersionAnalysis
  class Github
    URL = "https://api.github.com/graphql".freeze

    HttpAdapter = GraphQL::Client::HTTP.new(URL) do
      def headers(_context)
        {
          "Authorization" => "Bearer #{ENV['GITHUB_IMPORT_TOKEN']}",
          "User-Agent" => "Ruby",
        }
      end
    end
    Schema = GraphQL::Client.load_schema(HttpAdapter)
    Client = GraphQL::Client.new(schema: Schema, execute: HttpAdapter)

    def initialize; end

    AlertsQuery = Github::Client.parse <<-'GRAPHQL'
      query($name: String!) {
        repository(name: $name, owner: "GetJobber") {
          vulnerabilityAlerts(first: 100) {
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
                }
                severity
              }
              number
            }
            pageInfo {
              endCursor
              hasNextPage
            }
          }
        }
      }
    GRAPHQL

    AlertsQueryNext = Github::Client.parse <<-'GRAPHQL'
      query($name: String!, $cursor: String!) {
        repository(name: $name, owner: "GetJobber") {
          vulnerabilityAlerts(first: 100, after: $cursor) {
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
                }
                severity
              }
              number
            }
            pageInfo {
              endCursor
              hasNextPage
            }
          }
        }
      }
    GRAPHQL

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
            cvss: cvss
          )
          parsed_results[package] = vv
        end

        meta_data.total_cvss = meta_data.total_cvss + 1
      end
    end

    def find_alerts(github_name, ecosystem)
      response = Github::Client.query(AlertsQuery, variables: { name: github_name })

      alerts = {}

      if response.errors.any?
        raise QueryExecutionError, response.errors[:data].join(", ")
      else
        end_cursor = add_results(response.data.repository.vulnerability_alerts, alerts, ecosystem)
        end_cursor = nil # Until github issue is resolved.
        until end_cursor.nil?
          response = Github::Client.query(AlertsQueryNext, variables: { name: github_name, cursor: end_cursor })
          end_cursor = add_results(response.data.repository.vulnerability_alerts, alerts, ecosystem)
        end
      end

      return alerts
    end

    def add_results(alerts, results, target_ecosystem)
      alerts.nodes.each do |alert|
        databaseId = alert.security_vulnerability.advisory.database_id
        ecosystem = alert.security_vulnerability.package.ecosystem

        if ecosystem == target_ecosystem && !results.has_key?(databaseId)
          results[databaseId] = {
            package: alert.security_vulnerability.package.name,
            identifiers: alert.security_vulnerability.advisory.identifiers.map(&:value),
            severity: alert.security_vulnerability.severity,
          }
        end
      end

      end_cursor = alerts.page_info.has_next_page ? alerts.page_info.end_cursor : nil
      return end_cursor
    end
  end
end
