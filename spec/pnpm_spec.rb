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
      # nil => resolved set could not be determined, so the workspace-scope filter is skipped
      # and the libyear-derived results below are retained (this context exercises that wiring).
      allow(analyzer).to receive(:add_all_libraries).and_return(nil)

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

    it "should build graph from devDependencies when no dependencies exist" do
      pnpm_dev_only = <<~DOC
        [
          {
            "name": "workspace-pkg",
            "version": "1.0.0",
            "devDependencies": {
              "a": {
                "version": "1.0.0",
                "dependencies": {
                  "b": {
                    "version": "2.0.0"
                  }
                }
              }
            }
          }
        ]
      DOC

      parsed_results = { "a" => {}, "b" => {} }

      analyzer = LibraryVersionAnalysis::Pnpm.new("test")
      allow(analyzer).to receive(:run_pnpm_list).and_return(pnpm_dev_only)
      result = analyzer.add_dependency_graph(parsed_results)

      expect(result.count).to eq(2)
      expect(result["b"].parents[0].name).to eq("a")
    end

    it "should build graph from both dependencies and devDependencies" do
      pnpm_mixed = <<~DOC
        [
          {
            "name": "workspace-pkg",
            "version": "1.0.0",
            "dependencies": {
              "a": {
                "version": "1.0.0",
                "dependencies": {
                  "shared": {
                    "version": "3.0.0"
                  }
                }
              }
            },
            "devDependencies": {
              "b": {
                "version": "2.0.0",
                "dependencies": {
                  "shared": {
                    "version": "3.0.0"
                  }
                }
              }
            }
          }
        ]
      DOC

      parsed_results = { "a" => {}, "b" => {}, "shared" => {} }

      analyzer = LibraryVersionAnalysis::Pnpm.new("test")
      allow(analyzer).to receive(:run_pnpm_list).and_return(pnpm_mixed)
      result = analyzer.add_dependency_graph(parsed_results)

      expect(result.count).to eq(3)
      expect(result["shared"].parents.count).to eq(2)
      parent_names = result["shared"].parents.map(&:name)
      expect(parent_names).to contain_exactly("a", "b")
    end

    it "should gracefully handle pnpm list failure" do
      parsed_results = { "a" => {}, "b" => {} }

      analyzer = LibraryVersionAnalysis::Pnpm.new("test")
      allow(analyzer).to receive(:run_pnpm_list).and_return(nil)

      expect { analyzer.add_dependency_graph(parsed_results) }.not_to raise_error
      result = analyzer.add_dependency_graph(parsed_results)

      expect(result).to eq({})
      # Verify parsed_results is unchanged (no dependency_graph added)
      expect(parsed_results["a"]["dependency_graph"]).to be_nil
      expect(parsed_results["b"]["dependency_graph"]).to be_nil
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

  describe "#add_all_libraries" do
    let(:analyzer) { LibraryVersionAnalysis::Pnpm.new("test") }

    let(:pnpm_list_json) do
      <<~DOC
        [
          {
            "name": "workspace-root",
            "version": "1.0.0",
            "path": "/project",
            "dependencies": {
              "@apollo/client": { "from": "@apollo/client", "version": "3.13.8" },
              "wrangler": { "from": "wrangler", "version": "4.76.0" }
            },
            "devDependencies": {
              "@jobberfe/tsconfig": { "from": "@jobberfe/tsconfig", "version": "link:packages/tsconfig" },
              "internal-pkg": { "from": "internal-pkg", "version": "workspace:*" }
            }
          },
          {
            "name": "jobber-online",
            "version": "1.0.0",
            "path": "/project/apps/jobber-online",
            "dependencies": {
              "@apollo/client": { "from": "@apollo/client", "version": "3.13.8" }
            },
            "devDependencies": {
              "storybook": { "from": "storybook", "version": "9.0.16" }
            }
          },
          {
            "name": "core",
            "version": "1.0.0",
            "path": "/project/packages/core",
            "dependencies": {
              "lodash": { "from": "lodash", "version": "4.17.21" }
            },
            "devDependencies": {}
          }
        ]
      DOC
    end

    before do
      allow(analyzer).to receive(:run_pnpm_list_depth0).and_return(pnpm_list_json)
    end

    it "resolves scoped and unscoped versions for the selected workspace" do
      result = analyzer.send(:add_all_libraries, "/project")

      expect(result["@apollo/client"].current_version).to eq("3.13.8")
      expect(result["wrangler"].current_version).to eq("4.76.0")
    end

    it "produces different results per workspace" do
      online = analyzer.send(:add_all_libraries, "/project/apps/jobber-online")
      core = analyzer.send(:add_all_libraries, "/project/packages/core")

      expect(online).to have_key("storybook")
      expect(core).not_to have_key("storybook")
      expect(core["lodash"].current_version).to eq("4.17.21")
    end

    it "skips link: and workspace: specifiers (no installed version)" do
      result = analyzer.send(:add_all_libraries, "/project")

      expect(result).not_to have_key("@jobberfe/tsconfig")
      expect(result).not_to have_key("internal-pkg")
    end

    it "combines multiple resolved versions into a range" do
      multi = <<~DOC
        [
          {
            "name": "workspace-root",
            "path": "/project",
            "dependencies": { "pkg": { "version": "4.54.0" } },
            "devDependencies": { "pkg": { "version": "4.76.0" } }
          }
        ]
      DOC
      allow(analyzer).to receive(:run_pnpm_list_depth0).and_return(multi)

      result = analyzer.send(:add_all_libraries, "/project")

      expect(result["pkg"].current_version).to eq("4.54.0..4.76.0")
    end

    it "returns nil and warns when no workspace entry matches" do
      expect(analyzer).to receive(:warn).with(/Could not find pnpm list entry/)

      result = analyzer.send(:add_all_libraries, "/project/apps/does-not-exist")

      expect(result).to be_nil
    end

    it "uses the only entry for a single-package repo (no workspace_path)" do
      single = <<~DOC
        [
          {
            "name": "solo",
            "path": "/project",
            "dependencies": { "lodash": { "version": "4.17.21" } },
            "devDependencies": {}
          }
        ]
      DOC
      allow(analyzer).to receive(:run_pnpm_list_depth0).and_return(single)

      result = analyzer.send(:add_all_libraries)

      expect(result["lodash"].current_version).to eq("4.17.21")
    end

    it "returns nil on pnpm list failure" do
      allow(analyzer).to receive(:run_pnpm_list_depth0).and_return(nil)

      expect(analyzer.send(:add_all_libraries, "/project")).to be_nil
    end

    it "returns an empty hash (not nil) when the workspace has no resolvable deps" do
      empty_ws = <<~DOC
        [
          {
            "name": "tsconfig",
            "path": "/project",
            "dependencies": {},
            "devDependencies": { "sibling": { "version": "link:../sibling" } }
          }
        ]
      DOC
      allow(analyzer).to receive(:run_pnpm_list_depth0).and_return(empty_ws)

      result = analyzer.send(:add_all_libraries, "/project")

      expect(result).to eq({})
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

  describe "#source_name_for_workspace" do
    let(:analyzer) { LibraryVersionAnalysis::Pnpm.new("test") }

    it "should return 'root' for the root workspace path" do
      allow(Dir).to receive(:pwd).and_return("/project")
      expect(analyzer.source_name_for_workspace("/project")).to eq("root")
    end

    it "should return 'root' for '.' path" do
      allow(Dir).to receive(:pwd).and_return("/project")
      expect(analyzer.source_name_for_workspace("/project")).to eq("root")
    end

    it "should return relative path for nested workspace" do
      allow(Dir).to receive(:pwd).and_return("/project")
      expect(analyzer.source_name_for_workspace("/project/apps/anchor")).to eq("apps/anchor")
    end

    it "should return relative path for packages workspace" do
      allow(Dir).to receive(:pwd).and_return("/project")
      expect(analyzer.source_name_for_workspace("/project/packages/bits")).to eq("packages/bits")
    end
  end

  describe "#single_package_repo?" do
    let(:analyzer) { LibraryVersionAnalysis::Pnpm.new("test") }

    before do
      allow(Dir).to receive(:pwd).and_return("/project")
    end

    it "should return true for single package at root" do
      workspaces = [{ "name" => "my-app", "path" => "/project" }]
      expect(analyzer.single_package_repo?(workspaces)).to be true
    end

    it "should return false for multiple workspaces" do
      workspaces = [
        { "name" => "root", "path" => "/project" },
        { "name" => "app-a", "path" => "/project/apps/app-a" }
      ]
      expect(analyzer.single_package_repo?(workspaces)).to be false
    end

    it "should return false for single workspace not at root" do
      workspaces = [{ "name" => "app-a", "path" => "/project/apps/app-a" }]
      expect(analyzer.single_package_repo?(workspaces)).to be false
    end
  end

  describe "#libyear_filename_for_source" do
    let(:analyzer) { LibraryVersionAnalysis::Pnpm.new("test") }

    it "should return 'libyear_report.txt' for 'pnpm' source (backwards compatible)" do
      expect(analyzer.send(:libyear_filename_for_source, "pnpm")).to eq("libyear_report.txt")
    end

    it "should return 'libyear_root.txt' for 'root' source" do
      expect(analyzer.send(:libyear_filename_for_source, "root")).to eq("libyear_root.txt")
    end

    it "should convert slashes to hyphens for nested paths" do
      expect(analyzer.send(:libyear_filename_for_source, "apps/anchor")).to eq("libyear_apps-anchor.txt")
    end

    it "should handle deeply nested paths" do
      expect(analyzer.send(:libyear_filename_for_source, "packages/ui/components")).to eq("libyear_packages-ui-components.txt")
    end
  end

  describe "#get_versions_for_all_workspaces" do
    let(:analyzer) { LibraryVersionAnalysis::Pnpm.new("test") }

    let(:libyear_root) do
      '[{"dependency": "typescript", "drift": 0.5, "major": 0, "minor": 1, "patch": 2, "available": "5.0.0"}]'
    end

    let(:libyear_apps_anchor) do
      '[{"dependency": "react", "drift": 0.3, "major": 0, "minor": 0, "patch": 1, "available": "18.2.0"}]'
    end

    context "with workspace repo (multiple workspaces)" do
      let(:workspaces) do
        [
          { "name" => "root", "path" => "/project" },
          { "name" => "@jobber/anchor", "path" => "/project/apps/anchor" }
        ]
      end

      before do
        allow(Dir).to receive(:pwd).and_return("/project")
        allow(analyzer).to receive(:discover_workspaces).and_return(workspaces)
        allow(analyzer).to receive(:get_versions_for_workspace).with("/project", "root").and_return([{ "typescript" => {} }, double(total_age: 0.5)])
        allow(analyzer).to receive(:get_versions_for_workspace).with("/project/apps/anchor", "apps/anchor").and_return([{ "react" => {} }, double(total_age: 0.3)])
      end

      it "should return hash with multiple workspace sources" do
        result = analyzer.get_versions_for_all_workspaces

        expect(result.keys).to contain_exactly("root", "apps/anchor")
      end

      it "should return results for root workspace" do
        result = analyzer.get_versions_for_all_workspaces

        expect(result["root"][:results]).to have_key("typescript")
      end

      it "should return results for nested workspace" do
        result = analyzer.get_versions_for_all_workspaces

        expect(result["apps/anchor"][:results]).to have_key("react")
      end
    end

    context "with non-workspace repo (single package at root)" do
      let(:workspaces) do
        [{ "name" => "my-simple-app", "path" => "/project" }]
      end

      before do
        allow(Dir).to receive(:pwd).and_return("/project")
        allow(analyzer).to receive(:discover_workspaces).and_return(workspaces)
        allow(analyzer).to receive(:get_versions).with("pnpm").and_return([{ "lodash" => {} }, double(total_age: 1.0)])
      end

      it "should return hash with single 'pnpm' source for backwards compatibility" do
        result = analyzer.get_versions_for_all_workspaces

        expect(result.keys).to eq(["pnpm"])
      end

      it "should call get_versions with 'pnpm' source" do
        expect(analyzer).to receive(:get_versions).with("pnpm")
        analyzer.get_versions_for_all_workspaces
      end

      it "should return results under 'pnpm' key" do
        result = analyzer.get_versions_for_all_workspaces

        expect(result["pnpm"][:results]).to have_key("lodash")
      end

      it "should return meta_data under 'pnpm' key" do
        result = analyzer.get_versions_for_all_workspaces

        expect(result["pnpm"][:meta_data].total_age).to eq(1.0)
      end
    end
  end

  describe "#filter_to_workspace_packages" do
    let(:analyzer) { LibraryVersionAnalysis::Pnpm.new("test") }

    it "should remove Dependabot-injected packages not in the workspace dependency tree" do
      workspace_package_names = Set["react", "lodash"]

      parsed_results = {
        "react" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown", current_version: "18.2.0"),
        "lodash" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown", current_version: "4.17.21"),
        "@grpc/grpc-js" => LibraryVersionAnalysis::Versionline.new(
          owner: LibraryVersionAnalysis::Configuration.get(:default_owner_name),
          current_version: "?",
          major: 0, minor: 0, patch: 0, age: 0,
          vulnerabilities: [LibraryVersionAnalysis::Vulnerability.new(identifier: ["CVE-2024-37168"], assigned_severity: "MODERATE")]
        )
      }

      analyzer.send(:filter_to_workspace_packages, parsed_results, workspace_package_names, "packages/visualizations")

      expect(parsed_results).to have_key("react")
      expect(parsed_results).to have_key("lodash")
      expect(parsed_results).not_to have_key("@grpc/grpc-js")
    end

    it "should not remove any packages when all are in the workspace" do
      workspace_package_names = Set["react", "lodash"]

      parsed_results = {
        "react" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown", current_version: "18.2.0"),
        "lodash" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown", current_version: "4.17.21")
      }

      analyzer.send(:filter_to_workspace_packages, parsed_results, workspace_package_names, "packages/visualizations")

      expect(parsed_results.keys).to contain_exactly("react", "lodash")
    end

    it "should keep vulnerable packages that are actually in the workspace" do
      workspace_package_names = Set["react", "vulnerable-lib"]

      parsed_results = {
        "react" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown", current_version: "18.2.0"),
        "vulnerable-lib" => LibraryVersionAnalysis::Versionline.new(
          owner: ":unknown", current_version: "1.0.0",
          vulnerabilities: [LibraryVersionAnalysis::Vulnerability.new(identifier: ["CVE-2024-00001"], assigned_severity: "HIGH")]
        )
      }

      analyzer.send(:filter_to_workspace_packages, parsed_results, workspace_package_names, "packages/visualizations")

      expect(parsed_results).to have_key("vulnerable-lib")
      expect(parsed_results["vulnerable-lib"].vulnerabilities).not_to be_empty
    end

    it "should handle empty parsed_results" do
      workspace_package_names = Set[]
      parsed_results = {}

      analyzer.send(:filter_to_workspace_packages, parsed_results, workspace_package_names, "root")

      expect(parsed_results).to be_empty
    end

    it "removes everything when the resolved set is empty (no deps in this workspace)" do
      parsed_results = {
        "react" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown", current_version: ""),
        "lodash" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown", current_version: "")
      }

      analyzer.send(:filter_to_workspace_packages, parsed_results, Set[], "packages/tsconfig")

      expect(parsed_results).to be_empty
    end

    it "skips filtering when the resolved set is nil (pnpm could not determine deps)" do
      allow(analyzer).to receive(:warn)
      parsed_results = {
        "react" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown", current_version: "")
      }

      analyzer.send(:filter_to_workspace_packages, parsed_results, nil, "apps/harbour")

      expect(parsed_results).to have_key("react")
    end

    it "should remove multiple injected packages from different workspaces" do
      workspace_package_names = Set["react"]

      parsed_results = {
        "react" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown", current_version: "18.2.0"),
        "@grpc/grpc-js" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown", current_version: "?",
          vulnerabilities: [LibraryVersionAnalysis::Vulnerability.new(identifier: ["CVE-2024-37168"], assigned_severity: "MODERATE")]),
        "some-other-vuln" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown", current_version: "?",
          vulnerabilities: [LibraryVersionAnalysis::Vulnerability.new(identifier: ["CVE-2024-99999"], assigned_severity: "HIGH")])
      }

      analyzer.send(:filter_to_workspace_packages, parsed_results, workspace_package_names, "packages/visualizations")

      expect(parsed_results.keys).to contain_exactly("react")
    end

    it "should filter correctly even when Dependabot mutates the same hash object" do
      # Simulates the real production flow: parse_libyear returns all_libraries as
      # parsed_results (same object). The snapshot of keys must be taken before
      # add_dependabot_findings mutates the hash, otherwise the filter is a no-op.
      shared_hash = {
        "react" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown", current_version: "18.2.0"),
        "lodash" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown", current_version: "4.17.21")
      }
      workspace_package_names = shared_hash.keys.to_set

      # Simulate what add_dependabot_findings does: inject cross-workspace packages
      shared_hash["@grpc/grpc-js"] = LibraryVersionAnalysis::Versionline.new(
        owner: ":unknown", current_version: "?",
        vulnerabilities: [LibraryVersionAnalysis::Vulnerability.new(identifier: ["CVE-2024-37168"], assigned_severity: "MODERATE")]
      )

      analyzer.send(:filter_to_workspace_packages, shared_hash, workspace_package_names, "packages/visualizations")

      expect(shared_hash).to have_key("react")
      expect(shared_hash).to have_key("lodash")
      expect(shared_hash).not_to have_key("@grpc/grpc-js")
    end
  end

  describe "#add_ownerships with workspace_path" do
    let(:analyzer) { LibraryVersionAnalysis::Pnpm.new("test") }

    let(:workspace_package_json) do
      {
        "lodash" => ":anchor_team",
        "react" => ":anchor_team"
      }
    end

    before do
      allow(analyzer).to receive(:read_package_json_ownerships).with("/project/apps/anchor/package.json").and_return(workspace_package_json)
      allow(analyzer).to receive(:add_transitive_ownerships)
      allow(analyzer).to receive(:add_attention_needed)
    end

    it "should apply ownership from workspace package.json when workspace_path provided" do
      parsed_results = {
        "lodash" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown"),
        "react" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown")
      }

      analyzer.send(:add_ownerships, parsed_results, "/project/apps/anchor")

      expect(parsed_results["lodash"].owner).to eq(":anchor_team")
      expect(parsed_results["react"].owner).to eq(":anchor_team")
    end

    it "should set owner_reason to ASSIGNED for workspace ownerships" do
      parsed_results = {
        "lodash" => LibraryVersionAnalysis::Versionline.new(owner: ":unknown")
      }

      analyzer.send(:add_ownerships, parsed_results, "/project/apps/anchor")

      expect(parsed_results["lodash"].owner_reason).to eq(LibraryVersionAnalysis::Ownership::OWNER_REASON_ASSIGNED)
    end

    it "should not change owner for libraries not in workspace package.json" do
      parsed_results = {
        "unknown-lib" => LibraryVersionAnalysis::Versionline.new(owner: ":default")
      }

      analyzer.send(:add_ownerships, parsed_results, "/project/apps/anchor")

      expect(parsed_results["unknown-lib"].owner).to eq(":default")
    end
  end

  describe "#get_versions_for_workspace libyear scoping" do
    let(:analyzer) { LibraryVersionAnalysis::Pnpm.new("test") }

    def versionline(current)
      LibraryVersionAnalysis::Versionline.new(owner: ":unknown", current_version: current)
    end

    # libyear reports a name that IS in the resolved set (react) and a foreign one
    # (@fullcalendar/core) that belongs to another workspace via the merged-union libyear file.
    let(:libyear) do
      '[{"dependency":"react","drift":0.3,"major":1,"minor":2,"patch":3,"available":"19.0.0"},' \
      '{"dependency":"@fullcalendar/core","drift":1.7,"major":1,"minor":10,"patch":7,"available":"5.10.1"}]'
    end

    before do
      allow(analyzer).to receive(:run_libyear_for_workspace).and_return(libyear)
      allow(analyzer).to receive(:add_dependabot_findings).and_return(nil)
      allow(analyzer).to receive(:add_dependency_graph).and_return({})
      allow(analyzer).to receive(:break_cycles)
      allow(analyzer).to receive(:add_ownerships)
    end

    it "drops libyear-only deps not in the resolved workspace set" do
      allow(analyzer).to receive(:add_all_libraries).with("/project/apps/jobber-online")
                                                    .and_return({ "react" => versionline("19.2.3") })

      parsed, = analyzer.get_versions_for_workspace("/project/apps/jobber-online", "apps/jobber-online")

      expect(parsed).to have_key("react")
      expect(parsed).not_to have_key("@fullcalendar/core")
    end

    it "retains and enriches a dep present in both the resolved set and libyear" do
      allow(analyzer).to receive(:add_all_libraries).with("/project/apps/jobber-online")
                                                    .and_return({ "react" => versionline("19.2.3") })

      parsed, = analyzer.get_versions_for_workspace("/project/apps/jobber-online", "apps/jobber-online")

      expect(parsed["react"].current_version).to eq("19.2.3")
      expect(parsed["react"].latest_version).to eq("19.0.0")
      expect(parsed["react"].major).to eq(1)
      expect(parsed["react"].minor).to eq(2)
      expect(parsed["react"].patch).to eq(3)
    end

    it "keeps per-workspace results distinct (foreign libyear dep excluded)" do
      allow(analyzer).to receive(:add_all_libraries).with("/project/packages/core")
                                                    .and_return({ "lodash" => versionline("4.17.21") })

      parsed, = analyzer.get_versions_for_workspace("/project/packages/core", "packages/core")

      expect(parsed.keys).to contain_exactly("lodash")
      expect(parsed).not_to have_key("react")
      expect(parsed).not_to have_key("@fullcalendar/core")
    end

    it "drops the whole libyear union when the workspace resolves to no deps (empty set)" do
      # Empty hash = workspace was resolved and genuinely has no registry-versioned direct deps
      # (e.g. only link:/workspace: deps). The libyear union must NOT be uploaded as blanks.
      allow(analyzer).to receive(:add_all_libraries).and_return({})

      parsed, = analyzer.get_versions_for_workspace("/project/packages/tsconfig", "packages/tsconfig")

      expect(parsed).to be_empty
    end

    it "skips the filter (retains libyear data) when the resolved set cannot be determined (nil)" do
      allow(analyzer).to receive(:add_all_libraries).and_return(nil)
      allow(analyzer).to receive(:warn)

      parsed, = analyzer.get_versions_for_workspace("/project/apps/jobber-online", "apps/jobber-online")

      # pnpm could not determine deps: keep prior behavior rather than wiping.
      expect(parsed).to have_key("react")
      expect(parsed).to have_key("@fullcalendar/core")
    end
  end
end
