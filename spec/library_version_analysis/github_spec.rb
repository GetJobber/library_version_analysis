require "library_version_analysis/github"
require "date"

RSpec.describe LibraryVersionAnalysis::Github do
  let(:mock_alert_node) do
    OpenStruct.new(
      security_vulnerability: OpenStruct.new(
        package: OpenStruct.new(
          ecosystem: "NPM",
          name: "test-package"
        ),
        advisory: OpenStruct.new(
          database_id: "DB-1",
          identifiers: [
            OpenStruct.new(value: "CVE-2023-1234")
          ],
          permalink: "https://example.com/advisory"
        ),
        severity: "HIGH"
      ),
      created_at: "2023-01-01T00:00:00Z",
      state: "OPEN",
      fixed_at: nil
    )
  end

  let(:mock_fixed_alert_node) do
    OpenStruct.new(
      security_vulnerability: OpenStruct.new(
        package: OpenStruct.new(
          ecosystem: "NPM",
          name: "test-package-fixed"
        ),
        advisory: OpenStruct.new(
          database_id: "DB-2",
          identifiers: [
            OpenStruct.new(value: "CVE-2023-5678")
          ],
          permalink: "https://example.com/advisory-2"
        ),
        severity: "MEDIUM"
      ),
      created_at: "2023-01-01T00:00:00Z",
      state: "FIXED",
      fixed_at: "2023-06-01T00:00:00Z"
    )
  end

  let(:mock_different_ecosystem_alert) do
    OpenStruct.new(
      security_vulnerability: OpenStruct.new(
        package: OpenStruct.new(
          ecosystem: "RUBYGEMS",
          name: "test-gem"
        ),
        advisory: OpenStruct.new(
          database_id: "DB-3",
          identifiers: [
            OpenStruct.new(value: "CVE-2023-9012")
          ],
          permalink: "https://example.com/advisory-3"
        ),
        severity: "CRITICAL"
      ),
      created_at: "2023-01-01T00:00:00Z",
      state: "OPEN",
      fixed_at: nil
    )
  end

  let(:mock_response_data) do
    OpenStruct.new(
      repository: OpenStruct.new(
        vulnerability_alerts: OpenStruct.new(
          nodes: [mock_alert_node],
          page_info: OpenStruct.new(
            has_next_page: false,
            end_cursor: nil
          )
        )
      )
    )
  end

  let(:mock_response) do
    OpenStruct.new(
      data: mock_response_data,
      errors: []
    )
  end

  describe "#get_dependabot_findings" do
    let(:subject) { described_class.new }
    let(:parsed_results) { {} }
    let(:meta_data) { OpenStruct.new }

    before do
      allow(ENV).to receive(:[]).with('GITHUB_READ_API_TOKEN').and_return('dummy_token')
      allow_any_instance_of(described_class).to receive(:find_alerts).and_return({ "DB-1" => mock_alert_node })
    end

    it "raises error when GITHUB_READ_API_TOKEN is not set" do
      allow(ENV).to receive(:[]).with('GITHUB_READ_API_TOKEN').and_return(nil)
      expect { subject.get_dependabot_findings(parsed_results, meta_data, "test-repo", "npm") }
        .to raise_error("GITHUB_READ_API_TOKEN is not set")
    end

    it "sets total_cvss in meta_data" do
      subject.get_dependabot_findings(parsed_results, meta_data, "test-repo", "npm")
      expect(meta_data.total_cvss).to eq(1)
    end
  end

  describe "#get_closed_findings" do
    let(:subject) { described_class.new }
    let(:parsed_results) { {} }

    before do
      allow(ENV).to receive(:[]).with('GITHUB_READ_API_TOKEN').and_return('dummy_token')
      allow_any_instance_of(described_class).to receive(:find_alerts).and_return({ "DB-2" => mock_fixed_alert_node })
    end

    it "raises error when GITHUB_READ_API_TOKEN is not set" do
      allow(ENV).to receive(:[]).with('GITHUB_READ_API_TOKEN').and_return(nil)
      expect { subject.get_closed_findings(parsed_results, "test-repo", "npm") }
        .to raise_error("GITHUB_READ_API_TOKEN is not set")
    end

    it "calls find_alerts with correct parameters" do
      expect_any_instance_of(described_class).to receive(:find_alerts)
        .with("test-repo", false, "NPM")
      subject.get_closed_findings(parsed_results, "test-repo", "npm")
    end
  end

  describe "#add_alerts_working_set" do
    let(:subject) { described_class.new }

    context "when processing open alerts" do
      it "adds alerts for matching ecosystem" do
        response_alerts = OpenStruct.new(
          nodes: [mock_alert_node],
          page_info: OpenStruct.new(
            has_next_page: false,
            end_cursor: nil
          )
        )

        found_alerts = {}
        end_cursor = subject.add_alerts_working_set(response_alerts, found_alerts, nil, "NPM")

        expect(found_alerts.length).to eq(1)
        expect(found_alerts["DB-1"]).to include(
          package: "test-package",
          severity: "HIGH",
          state: "OPEN",
          fixed_at: nil
        )
        expect(end_cursor).to be_nil
      end

      it "filters out alerts from different ecosystems" do
        response_alerts = OpenStruct.new(
          nodes: [mock_alert_node, mock_different_ecosystem_alert],
          page_info: OpenStruct.new(
            has_next_page: false,
            end_cursor: nil
          )
        )

        found_alerts = {}
        subject.add_alerts_working_set(response_alerts, found_alerts, nil, "NPM")

        expect(found_alerts.length).to eq(1)
        expect(found_alerts.keys).to contain_exactly("DB-1")
      end

      it "handles pagination correctly" do
        response_alerts = OpenStruct.new(
          nodes: [mock_alert_node],
          page_info: OpenStruct.new(
            has_next_page: true,
            end_cursor: "cursor123"
          )
        )

        found_alerts = {}
        end_cursor = subject.add_alerts_working_set(response_alerts, found_alerts, nil, "NPM")

        expect(end_cursor).to eq("cursor123")
      end
    end

    context "when processing fixed alerts" do
      it "filters out fixed alerts before earliest target date" do
        earliest_target_date = DateTime.parse("2023-07-01")
        response_alerts = OpenStruct.new(
          nodes: [mock_fixed_alert_node],
          page_info: OpenStruct.new(
            has_next_page: false,
            end_cursor: nil
          )
        )

        found_alerts = {}
        subject.add_alerts_working_set(response_alerts, found_alerts, earliest_target_date, "NPM")

        expect(found_alerts).to be_empty
      end

      it "includes fixed alerts after earliest target date" do
        earliest_target_date = DateTime.parse("2023-05-01")
        response_alerts = OpenStruct.new(
          nodes: [mock_fixed_alert_node],
          page_info: OpenStruct.new(
            has_next_page: false,
            end_cursor: nil
          )
        )

        found_alerts = {}
        subject.add_alerts_working_set(response_alerts, found_alerts, earliest_target_date, "NPM")

        expect(found_alerts.length).to eq(1)
        expect(found_alerts["DB-2"]).to include(
          package: "test-package-fixed",
          severity: "MEDIUM",
          state: "FIXED",
          fixed_at: "2023-06-01T00:00:00Z"
        )
      end
    end

    context "when processing multiple alerts" do
      it "does not duplicate alerts with same database_id" do
        duplicate_alert = mock_alert_node.dup
        response_alerts = OpenStruct.new(
          nodes: [mock_alert_node, duplicate_alert],
          page_info: OpenStruct.new(
            has_next_page: false,
            end_cursor: nil
          )
        )

        found_alerts = {}
        subject.add_alerts_working_set(response_alerts, found_alerts, nil, "NPM")

        expect(found_alerts.length).to eq(1)
        expect(found_alerts.keys).to contain_exactly("DB-1")
      end

      it "processes multiple different alerts" do
        response_alerts = OpenStruct.new(
          nodes: [mock_alert_node, mock_fixed_alert_node],
          page_info: OpenStruct.new(
            has_next_page: false,
            end_cursor: nil
          )
        )

        found_alerts = {}
        subject.add_alerts_working_set(response_alerts, found_alerts, nil, "NPM")

        expect(found_alerts.length).to eq(2)
        expect(found_alerts.keys).to contain_exactly("DB-1", "DB-2")
      end
    end
  end

  describe "#add_alerts_to_parsed_results" do
    let(:subject) { described_class.new }
    let(:parsed_results) { {} }
    let(:alerts) do
      {
        "DB-1" => {
          package: "test-package",
          identifiers: ["CVE-2023-1234"],
          severity: "HIGH",
          created_at: "2023-01-01T00:00:00Z",
          permalink: "https://example.com/advisory",
          source: "NPM",
          state: "OPEN",
          fixed_at: nil
        }
      }
    end

    before do
      allow(LibraryVersionAnalysis::Configuration).to receive(:get)
        .with(:default_owner_name).and_return(":default")
    end

    it "adds new package to parsed results" do
      subject.add_alerts_to_parsed_results(parsed_results, alerts)
      expect(parsed_results["test-package"]).not_to be_nil
    end

    it "sets correct vulnerability information" do
      subject.add_alerts_to_parsed_results(parsed_results, alerts)
      vulnerability = parsed_results["test-package"].vulnerabilities.first
      expect(vulnerability.identifier).to eq(["CVE-2023-1234"])
      expect(vulnerability.state).to eq("OPEN")
      expect(vulnerability.assigned_severity).to eq("HIGH")
    end

    it "appends vulnerability to existing package" do
      parsed_results["test-package"] = OpenStruct.new(vulnerabilities: [])
      subject.add_alerts_to_parsed_results(parsed_results, alerts)
      expect(parsed_results["test-package"].vulnerabilities.length).to eq(1)
    end
  end
end 