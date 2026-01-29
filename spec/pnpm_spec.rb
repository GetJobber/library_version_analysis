Status = Struct.new(:exitstatus) unless defined?(Status)

RSpec.describe LibraryVersionAnalysis::Pnpm do
  let(:libyear_file) do
    <<~DOC
      [
        {"dependency": "@apollo/client","drift":0.8213552361396304,"pulse":0.02737850787132101,"releases":34,"major":0,"minor":2,"patch":32,"available":"3.5.10"},
        {"dependency":"@babel/polyfill","drift":1.8179329226557153,"pulse":1.3880903490759753,"releases":12,"major":0,"minor":50,"patch":5,"available":"7.12.1"},
        {"dependency":"@ctrl/ts-base32","drift":0.9965776865160849,"pulse":0.6078028747433265,"releases":7,"major":1,"minor":1,"patch":5,"available":"2.1.1"},
        {"dependency":"@cubejs-client/core","drift":1.2019164955509924,"pulse":0.008213552361396304,"releases":58,"major":0,"minor":5,"patch":53,"available":"0.29.29"},
        {"dependency":"@flatfile/adapter","drift":0.9609856262833676,"pulse":0.2600958247775496,"releases":26,"major":2,"minor":7,"patch":19,"available":"2.9.6"},
        {"dependency":"@flatfile/react","drift":0.8350444900752909,"pulse":0.2655715263518138,"releases":16,"major":2,"minor":3,"patch":12,"available":"3.0.1"},
        {"dependency":"@fullcalendar/core","drift":1.7248459958932238,"pulse":0.3394934976043806,"releases":18,"major":1,"minor":10,"patch":7,"available":"5.10.1"},
        {"dependency":"@fullcalendar/daygrid","drift":1.7248459958932238,"pulse":0.3394934976043806,"releases":18,"major":1,"minor":10,"patch":7,"available":"5.10.1"},
        {"dependency":"lodash","drift":1.7248459958932238,"pulse":0.3394934976043806,"releases":18,"major":6,"minor":10,"patch":7,"available":"5.10.1"}
      ]
    DOC
  end

  let(:root_package_file) do
    <<~DOC
      {
        "name": "workspace-root",
        "ownerships": {
          "@apollo/client": ":api_platform",
          "@formatjs/intl-displaynames": ":core",
          "@ctrl/ts-base32": ":core",
          "@cubejs-client/core": ":core",
          "@flatfile/react": ":api_platform",
          "@fullcalendar/core": ":api_platform",
          "@fullcalendar/daygrid": ":api_platform",
          "lodash": ":platform_team"
        }
      }
    DOC
  end

  def do_compare(result:, owner:, current_version:, latest_version:, major:, minor:, patch:, age:) # rubocop:disable Metrics/AbcSize, Metrics/ParameterLists
    expect(result[:owner]).to eq(owner)
    expect(result[:current_version]).to eq(current_version)
    expect(result[:latest_version]).to eq(latest_version)
    expect(result[:major]).to eq(major)
    expect(result[:minor]).to eq(minor)
    expect(result[:patch]).to eq(patch)
    expect(result[:age]).to eq(age)
  end

  context "with pnpm workspace" do
    subject do
      analyzer = LibraryVersionAnalysis::Pnpm.new("test")
      allow(analyzer).to receive(:read_file).with("libyear_report.txt", true).and_return(libyear_file)
      allow(analyzer).to receive(:read_package_json_ownerships).with("package.json").and_return(JSON.parse(root_package_file)["ownerships"])
      allow(analyzer).to receive(:run_pnpm_list).and_return(pnpm_list)
      allow(analyzer).to receive(:run_pnpm_list_recursive).and_return(pnpm_list_recursive)
      allow(analyzer).to receive(:discover_workspaces).and_return([])
      allow(analyzer).to receive(:add_dependabot_findings).and_return(nil)
      allow(analyzer).to receive(:add_all_libraries).and_return({})

      analyzer.get_versions("test")
    end

    let(:pnpm_list) do
      <<~DOC
        [
          {
            "name": "workspace-root",
            "version": "1.0.0",
            "dependencies": {
              "@apollo/client": {
                "version": "3.3.16",
                "dependencies": {
                  "@babel/polyfill": {
                    "version": "2.2.0"
                  }
                }
              },
              "@cubejs-client/core": {
                "version": "0.4.0",
                "dependencies": {
                  "@flatfile/adapter": {
                    "version": "2.2.0"
                  }
                }
              }
            }
          }
        ]
      DOC
    end

    let(:pnpm_list_recursive) do
      <<~DOC
        [
          {
            "name": "workspace-root",
            "dependencies": {
              "@apollo/client": {},
              "@babel/polyfill": {},
              "lodash": {}
            }
          }
        ]
      DOC
    end

    it "should get expected data for owned library" do
      do_compare(
        result: subject[0]["@apollo/client"],
        owner: ":api_platform",
        current_version: "",
        latest_version: "3.5.10",
        major: 0,
        minor: 2,
        patch: 32,
        age: 0.8
      )
    end

    it "should return expected data for transitive" do
      do_compare(
        result: subject[0]["@babel/polyfill"],
        owner: ":api_platform",
        current_version: "",
        latest_version: "7.12.1",
        major: 0,
        minor: 50,
        patch: 5,
        age: 1.8
      )
    end

    it "should calculate expected meta_data" do
      expect(subject[1].total_age).to eq(11.7)
      expect(subject[1].total_releases).to eq(9)
      expect(subject[1].total_major).to eq(13)
      expect(subject[1].total_minor).to eq(98)
      expect(subject[1].total_patch).to eq(147)
    end
  end

  describe "#add_dependency_graph" do
    let(:pnpm_short_list) do
      <<~DOC
        [
          {
            "name": "workspace-root",
            "version": "1.0.0",
            "dependencies": {
              "a": {
                "version": "1.1.35",
                "dependencies": {
                  "b": {
                    "version": "1.16.2",
                    "dependencies": {
                      "c": {
                        "version": "1.16.2"
                      }
                    }
                  }
                }
              }
            }
          }
        ]
      DOC
    end

    let(:pnpm_multi_parent) do
      <<~DOC
        [
          {
            "name": "workspace-root",
            "version": "1.0.0",
            "dependencies": {
              "a": {
                "version": "1.1.35",
                "dependencies": {
                  "b": {
                    "version": "1.16.2"
                  }
                }
              },
              "c": {
                "version": "1.1.36",
                "dependencies": {
                  "b": {
                    "version": "1.16.2"
                  }
                }
              }
            }
          }
        ]
      DOC
    end

    let(:pnpm_multi_workspace) do
      <<~DOC
        [
          {
            "name": "workspace-a",
            "dependencies": {
              "a": {
                "version": "1.1.35",
                "dependencies": {
                  "b": {
                    "version": "1.16.2"
                  }
                }
              }
            }
          },
          {
            "name": "workspace-b",
            "dependencies": {
              "c": {
                "version": "1.1.36",
                "dependencies": {
                  "d": {
                    "version": "1.16.2"
                  }
                }
              }
            }
          }
        ]
      DOC
    end

    it "should reverse simple chain" do
      parsed_results = { "a" => {}, "b" => {}, "c" => {} }

      analyzer = LibraryVersionAnalysis::Pnpm.new("test")
      allow(analyzer).to receive(:run_pnpm_list).and_return(pnpm_short_list)

      result = analyzer.add_dependency_graph(parsed_results)

      expect(result.count).to eq(3)
      c = result["c"]
      expect(c.parents[0].name).to eq("b")
      b = result["c"].parents[0]
      expect(b.parents[0].name).to eq("a")
      a = result["c"].parents[0].parents[0]
      expect(a.parents).to be_nil
    end

    it "should handle multiple parents" do
      parsed_results = { "a" => {}, "b" => {}, "c" => {} }

      analyzer = LibraryVersionAnalysis::Pnpm.new("test")
      allow(analyzer).to receive(:run_pnpm_list).and_return(pnpm_multi_parent)
      result = analyzer.add_dependency_graph(parsed_results)

      b = result["b"]
      expect(b.parents.count).to eq(2)
    end

    it "should handle multiple workspaces" do
      parsed_results = { "a" => {}, "b" => {}, "c" => {}, "d" => {} }

      analyzer = LibraryVersionAnalysis::Pnpm.new("test")
      allow(analyzer).to receive(:run_pnpm_list).and_return(pnpm_multi_workspace)
      result = analyzer.add_dependency_graph(parsed_results)

      expect(result.count).to eq(4)
      expect(result["a"]).not_to be_nil
      expect(result["b"]).not_to be_nil
      expect(result["c"]).not_to be_nil
      expect(result["d"]).not_to be_nil
    end
  end

  describe "#break_cycles" do
    let(:pnpm_cycle) do
      <<~DOC
        [
          {
            "name": "workspace-root",
            "version": "1.0.0",
            "dependencies": {
              "a": {
                "version": "1.1.35"
              },
              "browserslist": {
                "version": "4.21.5",
                "dependencies": {
                  "node-releases": {
                    "version": "2.0.10"
                  },
                  "update-browserslist-db": {
                    "version": "1.0.10",
                    "dependencies": {
                      "browserslist": {
                        "version": "4.21.5"
                      },
                      "escalade": {
                        "version": "3.1.1"
                      }
                    }
                  }
                }
              }
            }
          }
        ]
      DOC
    end

    it "should nil out parents of library with cycle" do
      parsed_results = { "a" => {}, "browserslist" => {}, "node-releases" => {}, "update-browserslist-db" => {}, "escalade" => {} }
      analyzer = LibraryVersionAnalysis::Pnpm.new("test")
      allow(analyzer).to receive(:run_pnpm_list).and_return(pnpm_cycle)

      analyzer.add_dependency_graph(parsed_results)
      expect(parsed_results["browserslist"]["dependency_graph"].parents.find { |x| x.name == "update-browserslist-db" }.parents.length).to eq(1)

      analyzer.send(:break_cycles, parsed_results)
      expect(parsed_results["browserslist"]["dependency_graph"].parents.find { |x| x.name == "update-browserslist-db" }.parents.length).to eq(0)
    end
  end

  describe "#calculate_version" do
    let(:analyzer) { LibraryVersionAnalysis::Pnpm.new("test") }

    it("should return simple version if both match") do
      expect(analyzer.send(:calculate_version, "1.2.3", "1.2.3")).to eq("1.2.3")
    end

    it("should return correct order if new is greater than simple old") do
      expect(analyzer.send(:calculate_version, "1.2.3", "2.1.3")).to eq("1.2.3..2.1.3")
    end

    it("should return correct order if new is less than simple old") do
      expect(analyzer.send(:calculate_version, "2.1.4", "2.1.3")).to eq("2.1.3..2.1.4")
    end

    it("should replace left if new is less than left") do
      expect(analyzer.send(:calculate_version, "1.2.4..2.1.3", "1.2.3")).to eq("1.2.3..2.1.3")
    end

    it("should replace right if new is greater than right") do
      expect(analyzer.send(:calculate_version, "1.2.3..2.1.3", "2.2.3")).to eq("1.2.3..2.2.3")
    end

    it("should make no change if new is between left and right") do
      expect(analyzer.send(:calculate_version, "1.2.3..2.1.3", "1.3.3")).to eq("1.2.3..2.1.3")
    end
  end

  describe "#cascading_ownerships" do
    let(:analyzer) { LibraryVersionAnalysis::Pnpm.new("test") }

    let(:root_ownerships) do
      {
        "lodash" => ":platform_team",
        "react" => ":frontend_team",
        "shared-lib" => ":core_team"
      }
    end

    let(:workspace_ownerships) do
      {
        "app-a" => {
          "lodash" => ":app_a_team",
          "custom-lib" => ":app_a_team"
        },
        "app-b" => {
          "another-lib" => ":app_b_team"
        }
      }
    end

    let(:library_workspace_map) do
      {
        "lodash" => "app-a",
        "custom-lib" => "app-a",
        "react" => "app-b",
        "another-lib" => "app-b",
        "shared-lib" => nil
      }
    end

    before do
      allow(analyzer).to receive(:build_library_workspace_map).and_return(library_workspace_map)
    end

    it "should use workspace ownership when defined" do
      parsed_results = {
        "lodash" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown")
      }

      analyzer.send(:apply_cascading_ownerships, parsed_results, root_ownerships, workspace_ownerships)

      expect(parsed_results["lodash"].owner).to eq(":app_a_team")
    end

    it "should fall back to root ownership when workspace does not define" do
      parsed_results = {
        "react" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown")
      }

      analyzer.send(:apply_cascading_ownerships, parsed_results, root_ownerships, workspace_ownerships)

      expect(parsed_results["react"].owner).to eq(":frontend_team")
    end

    it "should use root ownership when library has no workspace" do
      parsed_results = {
        "shared-lib" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown")
      }

      analyzer.send(:apply_cascading_ownerships, parsed_results, root_ownerships, workspace_ownerships)

      expect(parsed_results["shared-lib"].owner).to eq(":core_team")
    end

    it "should not change owner when no ownership is defined" do
      parsed_results = {
        "undefined-lib" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown")
      }

      analyzer.send(:apply_cascading_ownerships, parsed_results, root_ownerships, workspace_ownerships)

      expect(parsed_results["undefined-lib"].owner).to eq(":unknown")
    end

    it "should set owner_reason to ASSIGNED when owner is found" do
      parsed_results = {
        "lodash" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown")
      }

      analyzer.send(:apply_cascading_ownerships, parsed_results, root_ownerships, workspace_ownerships)

      expect(parsed_results["lodash"].owner_reason).to eq(LibraryVersionAnalysis::Ownership::OWNER_REASON_ASSIGNED)
    end
  end

  describe "#discover_workspaces" do
    let(:analyzer) { LibraryVersionAnalysis::Pnpm.new("test") }

    let(:pnpm_workspace_list) do
      <<~DOC
        [
          {
            "name": "workspace-root",
            "path": "/project"
          },
          {
            "name": "@scope/app-a",
            "path": "/project/packages/app-a"
          },
          {
            "name": "@scope/app-b",
            "path": "/project/packages/app-b"
          }
        ]
      DOC
    end

    it "should return workspace packages" do
      allow(Open3).to receive(:capture3).with("pnpm list -r --depth=-1 --json").and_return([pnpm_workspace_list, "", Status.new(0)])

      result = analyzer.send(:discover_workspaces)

      expect(result.length).to eq(3)
      expect(result[0]["name"]).to eq("workspace-root")
      expect(result[1]["name"]).to eq("@scope/app-a")
      expect(result[1]["path"]).to eq("/project/packages/app-a")
    end

    it "should return empty array on failure" do
      allow(Open3).to receive(:capture3).with("pnpm list -r --depth=-1 --json").and_return(["", "error", Status.new(1)])

      result = analyzer.send(:discover_workspaces)

      expect(result).to eq([])
    end
  end
end
