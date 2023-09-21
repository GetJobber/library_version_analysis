Status = Struct.new(:exitstatus)

RSpec.describe LibraryVersionAnalysis::Npm do
  let(:npxfile) do
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
        {"dependency":"@t2","drift":1.7248459958932238,"pulse":0.3394934976043806,"releases":18,"major":6,"minor":10,"patch":7,"available":"5.10.1"}
      ]
    DOC
  end
  let(:packagefile) do
    <<~DOC
      {
        "ownerships": {
          "@apollo/client": ":api_platform",
          "@formatjs/intl-displaynames": ":core",
          "@ctrl/ts-base32": ":core",
          "@cubejs-client/core": ":core",
          "@flatfile/react": ":api_platform",
          "@fullcalendar/core": ":api_platform",
          "@fullcalendar/daygrid": ":api_platform",
          "@t2": ":api_platform",
          "@t3": ":api_platform"
        }
      }
    DOC
  end
  let(:npmlist) do
    <<~DOC
      jobber-mobile@4.73.0 /Users/johnz/source/jobber-mobile
      ├─┬ @apollo/client@3.3.16
      │ ├── @graphql-typed-document-node/core@3.1.0
      │ ├── @types/zen-observable@0.8.0
      │ ├─┬ @wry/context@0.6.0
      │ │ └── @babel/polyfill@2.2.0
      ├─┬ @cubejs-client/core@0.4.0
      │ │ └── @flatfile/adapter@2.2.0
      │ ├── fast-json-stable-stringify@2.1.0
      │ ├─┬ graphql-tag@2.12.4
      │ │ └── tslib@2.2.0
    DOC
  end

  def do_compare(result:, owner:, current_version:, latest_version:, major:, minor:, patch:, age:)
    expect(result[:owner]).to eq(owner)
    expect(result[:current_version]).to eq(current_version)
    expect(result[:latest_version]).to eq(latest_version)
    expect(result[:major]).to eq(major)
    expect(result[:minor]).to eq(minor)
    expect(result[:patch]).to eq(patch)
    expect(result[:age]).to eq(age)
  end

  context "with legacy app" do
    subject do
      analyzer = LibraryVersionAnalysis::Npm.new("test")
      allow(analyzer).to receive(:read_file).with("libyear_report.txt", true).and_return(npxfile)
      allow(analyzer).to receive(:read_file).with("package.json", false).and_return(packagefile)
      allow(analyzer).to receive(:run_npm_list).and_return(npmlist)
      allow(analyzer).to receive(:add_dependabot_findings).and_return(nil) # TODO: will need to retest this
      allow(analyzer).to receive(:add_ownership_from_transitive).and_return(nil) # TODO: will need to retest after we address ownerships

      analyzer.get_versions
    end

    before(:each) do
      allow(LibraryVersionAnalysis::CheckVersionStatus).to receive(:is_legacy?).and_return(true)
    end

    it "should get expected data for owned gem" do
      do_compare(
        result: subject[0]["@apollo/client"],
        owner: ":api_platform",
        current_version: "3.3.16",
        latest_version: "3.5.10",
        major: 0,
        minor: 2,
        patch: 32,
        age: 0.8
      )
    end

    it "should returns expected data for transitive" do
      do_compare(
        result: subject[0]["@babel/polyfill"],
        owner: ":api_platform",
        current_version: "2.2.0",
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

  context "with new app" do
    before(:each) do
      allow(LibraryVersionAnalysis::CheckVersionStatus).to receive(:is_legacy?).and_return(false)
    end

    describe "#add_dependency_graph" do
      let(:npm_list) do
        results = <<~EOR
          {
            "version": "1.0.0",
            "name": "jobber",
            "problems": [
              "invalid: stylelint@14.16.1 /Users/johnz/source/Jobber/node_modules/stylelint"
            ],
            "dependencies": {
              "a": {
                "version": "1.1.35",
                "resolved": "https://registry.npmjs.org/@googlemaps/react-wrapper/-/react-wrapper-1.1.35.tgz",
                "overridden": false,
                "dependencies": {
                  "b": {
                    "version": "1.16.2",
                    "resolved": "https://registry.npmjs.org/@googlemaps/js-api-loader/-/js-api-loader-1.16.2.tgz",
                    "overridden": false,
                    "dependencies": {
                      "c": {
                        "version": "3.1.3"
                      },
                      "d": {
                        "version": "3.1.3"
                      }
                    }
                  }
                }
              }
            }
          }
        EOR

        return results
      end

      let(:npm_short_list) do
        results = <<~EOR
          {
            "version": "1.0.0",
            "name": "jobber",
            "problems": [
              "invalid: stylelint@14.16.1 /Users/johnz/source/Jobber/node_modules/stylelint"
            ],
            "dependencies": {
              "a": {
                "version": "1.1.35",
                "resolved": "https://registry.npmjs.org/@googlemaps/react-wrapper/-/react-wrapper-1.1.35.tgz",
                "overridden": false,
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
        EOR
        return results
      end

      let(:npm_cycle) do
        results = <<~EOR
          {
            "version": "1.0.0",
            "name": "jobber",
            "dependencies": {
              "a": {  
                "version": "1.1.35"
               },
              "browserslist": {
                "version": "4.21.5",
                "resolved": "https://registry.npmjs.org/browserslist/-/browserslist-4.21.5.tgz",
                "overridden": false,
                "dependencies": {
                  "node-releases": {
                    "version": "2.0.10",
                    "resolved": "https://registry.npmjs.org/node-releases/-/node-releases-2.0.10.tgz",
                    "overridden": false
                  },
                  "update-browserslist-db": {
                    "version": "1.0.10",
                    "resolved": "https://registry.npmjs.org/update-browserslist-db/-/update-browserslist-db-1.0.10.tgz",
                    "overridden": false,
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
        EOR

        return results
      end

      it "should reverse simple chain" do
        parsed_results = {"a" => {}, "b" => {}, "c" => {}}

        analyzer = LibraryVersionAnalysis::Npm.new("test")
        allow(analyzer).to receive(:run_npm_list).and_return(npm_short_list)

        result = analyzer.add_dependency_graph(parsed_results)

        expect(result.count).to eq(3)
        c = result["c"]
        expect(c.parents[0].name).to eq("b")
        b = result["c"].parents[0]
        expect(b.parents[0].name).to eq("a")
        a = result["c"].parents[0].parents[0]
        expect(a.parents).to be_nil
      end

      it "should handle two leaf tree" do
        parsed_results = {"a" => {}, "b" => {}, "c" => {}, "d" => {}}

        analyzer = LibraryVersionAnalysis::Npm.new("test")
        allow(analyzer).to receive(:run_npm_list).and_return(npm_list)
        result = analyzer.add_dependency_graph(parsed_results)

        expect(result.count).to eq(4)
        d = result["d"]
        expect(d.parents[0].name).to eq("b")
        c = result["c"]
        expect(c.parents[0].name).to eq("b")
        b = result["c"].parents[0]
        expect(b.parents[0].name).to eq("a")
        a = result["c"].parents[0].parents[0]
        expect(a.parents).to be_nil
      end

      it "should nil out parents of library with cycle" do
        parsed_results = {"a" => {}, "browserslist" => {}, "node-releases" => {}, "update-browserslist-db" => {}, "escalade" => {}}
        analyzer = LibraryVersionAnalysis::Npm.new("test")
        allow(analyzer).to receive(:run_npm_list).and_return(npm_cycle)

        result = analyzer.add_dependency_graph(parsed_results)

        expect(result["browserslist"].parents).to be_nil
      end
    end

    describe "#calculate_version" do
      let(:analyzer) { LibraryVersionAnalysis::Npm.new("test") }

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
  end
end
