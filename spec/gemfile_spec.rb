Status = Struct.new(:exitstatus)

# Mocks the Set returned by StructSet
SpecSetStruct = Struct.new(
  :name,
  :dependencies,
  keyword_init: true
) do
  def first
    return self
  end
end

# Mocks the behaviour of StructSet whose interface (that we need) is largely a hash, but each behaves as each_value
class ValueOnlyHash < Hash
  def each(&block)
    each_value(&block)
  end
end

RSpec.describe LibraryVersionAnalysis::Gemfile do
  let(:libyear_versions) do
    <<~DOC
            packwerk         1.0.3     2018-01-25          1.1.0     2020-11-12      [0, 1, 0]
               aasm          4.1.1     2020-08-11          5.2.0     2021-05-02      [1, 0, 0]
        actioncable        6.0.3.5     2021-02-10        7.0.2.2     2022-02-11      [1, 0, 0]
      transitivebox        5.0.3.5     2021-02-10        7.0.2.2     2022-02-11      [2, 0, 0]
    DOC
  end
  let(:libyear_libyear) do
    <<~DOC
           packwerk          1.0.3     2018-01-25          1.1.0     2020-11-12       2.8
               aasm          4.1.1     2020-08-11          5.2.0     2021-05-02       0.7
        actioncable        6.0.3.5     2021-02-10        7.0.2.2     2022-02-11       1.0
      transitivebox        5.0.3.5     2021-02-10        7.0.2.2     2022-02-11       1.0
    DOC
  end
  let(:gemfile) do
    <<~DOC
      jgem :core, "aasm", '>= 5.0.6'
      jgem :self_serve, "packwerk"
    DOC
  end
  let(:bundle_why) do
    <<~DOC
      packwerk -> pdf-reader -> transitivebox
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

  context "with legacy app" do
    subject do
      analyzer = LibraryVersionAnalysis::Gemfile.new("Test")
      allow(analyzer).to receive(:run_libyear).with(/--versions/).and_return(libyear_versions)
      allow(analyzer).to receive(:run_libyear).with(/--libyear/).and_return(libyear_libyear)
      allow(analyzer).to receive(:add_remaining_libraries).and_return(libyear_libyear) # do nothing at this point
      allow(analyzer).to receive(:read_file).and_return(gemfile)
      allow(Open3).to receive(:capture3).and_return(["", "", Status.new(1)])
      allow(analyzer).to receive(:why_init).and_return(nil)
      allow(analyzer).to receive(:why).and_return(bundle_why)
      allow(analyzer).to receive(:add_dependabot_findings).and_return(nil) # TODO: will need to retest this
      allow(analyzer).to receive(:add_ownership_from_transitive).and_return(nil)
      allow(analyzer).to receive(:add_dependency_graph).and_return(bundle_why) # TODO: Need to upgrade legacy tests
      analyzer.get_versions("Test")
    end

    before(:each) do
      allow(LibraryVersionAnalysis::CheckVersionStatus).to receive(:legacy?).and_return(true)
    end

    it "should get expected data for owned gem" do
      do_compare(
        result: subject[0]["packwerk"],
        owner: ":self_serve",
        current_version: "1.0.3",
        latest_version: "1.1.0",
        major: 0,
        minor: 1,
        patch: 0,
        age: 2.8
      )
    end

    it "should returns expected data for special case gem" do
      do_compare(
        result: subject[0]["actioncable"],
        owner: ":api_platform",
        current_version: "6.0.3.5",
        latest_version: "7.0.2.2",
        major: 1,
        minor: 0,
        patch: 0,
        age: 1.0
      )
    end

    # TODO: restore this test after we address ownerships
    # it "should returns expected data for transitive" do
    #   do_compare(
    #     result: subject[0]["transitivebox"],
    #     owner: ":self_serve",
    #     current_version: "5.0.3.5",
    #     latest_version: "7.0.2.2",
    #     major: 2,
    #     minor: 0,
    #     patch: 0,
    #     age: 1.0
    #   )
    # end

    it "should calculate expected meta_data" do
      expect(subject[1].total_releases).to eq(4)
    end
  end

  context "with new app" do
    before(:each) do
      allow(LibraryVersionAnalysis::CheckVersionStatus).to receive(:legacy?).and_return(false)
    end

    describe "#add_dependency_graph" do
      it "should reverse simple chain" do
        c = SpecSetStruct.new(name: "c")
        b = SpecSetStruct.new(name: "b", dependencies: [c])
        a = SpecSetStruct.new(name: "a", dependencies: [b])

        full_spec_set = ValueOnlyHash.new
        full_spec_set["a"] = a
        full_spec_set["b"] = b
        full_spec_set["c"] = c

        parsed_results = {"a" => {}, "b" => {}, "c" => {}}

        analyzer = LibraryVersionAnalysis::Gemfile.new("test")
        result = analyzer.add_dependency_graph(full_spec_set, parsed_results)

        expect(result.count).to eq(3)
        c = result["c"]
        expect(c.parents[0].name).to eq("b")
        b = result["c"].parents[0]
        expect(b.parents[0].name).to eq("a")
        a = result["c"].parents[0].parents[0]
        expect(a.parents).to be_nil
      end

      it "should handle two leaf tree" do
        d = SpecSetStruct.new(name: "d")
        c = SpecSetStruct.new(name: "c")
        b = SpecSetStruct.new(name: "b", dependencies: [c, d])
        a = SpecSetStruct.new(name: "a", dependencies: [b])

        full_spec_set = ValueOnlyHash.new
        full_spec_set["a"] = a
        full_spec_set["b"] = b
        full_spec_set["c"] = c
        full_spec_set["d"] = d

        parsed_results = {"a" => {}, "b" => {}, "c" => {}, "d" => {}}

        analyzer = LibraryVersionAnalysis::Gemfile.new("test")
        result = analyzer.add_dependency_graph(full_spec_set, parsed_results)

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
    end
  end
end
