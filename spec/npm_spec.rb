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

  context "when mobile" do
    subject do
      analyzer = LibraryVersionAnalysis::Npm.new
      allow(analyzer).to receive(:read_file).with("./libyear_report.txt", true).and_return(npxfile)
      allow(analyzer).to receive(:read_file).with("./package.json", false).and_return(packagefile)
      allow(analyzer).to receive(:run_npm_list).and_return(npmlist)

      analyzer.get_versions(".")
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
end
