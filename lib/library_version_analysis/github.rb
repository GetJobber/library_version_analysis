require "graphql/client"
require "graphql/client/http"
require "pry"

module LibraryVersionAnalysis
  class Github
    URL = "https://api.github.com/graphql"

    HttpAdapter = GraphQL::Client::HTTP.new(URL) do
      def headers(context)
        {
          "Authorization" => "Bearer " + ENV["GITHUB_IMPORT_TOKEN"],
          "User-Agent" => "Ruby",
        }
      end
    end
    Schema = GraphQL::Client.load_schema(HttpAdapter)
    Client = GraphQL::Client.new(schema: Schema, execute: HttpAdapter)

    def initialize
    end

    AlertsQuery = Github::Client.parse <<-'GRAPHQL'
      query {
        repository(name: "Jobber", owner: "GetJobber") {
          vulnerabilityAlerts(first: 100) {
            nodes {
              createdAt
              securityVulnerability {
                package {
                  name
                }
                advisory {
                  identifiers {
                    type
                    value
                  }
                  severity
                }
              }
            }
          }
        }
      }
    GRAPHQL

    def find_alerts(github_name)
      response = Github::Client.query(AlertsQuery)

      alerts = {}

      if response.errors.any?
        raise QueryExecutionError.new(response.errors[:data].join(", "))
      else
        response.data.repository.vulnerability_alerts.nodes.each do |alert|
          package = alert.security_vulnerability.package.name
          identifiers = alert.security_vulnerability.advisory.identifiers.map{ |type| type.value }
          severity = alert.security_vulnerability.advisory.severity

          alerts[package] = "#{severity} #{identifiers}"
        end
      end

      return alerts
    end
  end
end