Status = Struct.new(:exitstatus)

RSpec.describe LibraryVersionAnalysis::Online do
  let(:libyear_versions) do
    <<~DOC
            packwerk          1.0.3     2018-01-25          1.1.0     2020-11-12      [0, 1, 0]
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

  def do_compare(result:, owner:, current_version:, latest_version:, major:, minor:, patch:, age:)
    expect(result[:owner]).to eq(owner)
    expect(result[:current_version]).to eq(current_version)
    expect(result[:latest_version]).to eq(latest_version)
    expect(result[:major]).to eq(major)
    expect(result[:minor]).to eq(minor)
    expect(result[:patch]).to eq(patch)
    expect(result[:age]).to eq(age)
  end

  context "when online" do
    subject do
      analyzer = LibraryVersionAnalysis::Online.new
      allow(analyzer).to receive(:run_libyear).with(/--versions/).and_return(libyear_versions)
      allow(analyzer).to receive(:run_libyear).with(/--libyear/).and_return(libyear_libyear)
      allow(analyzer).to receive(:read_file).and_return(gemfile)
      allow(Open3).to receive(:capture3).and_return(["", "", Status.new(1)])
      allow(Open3).to receive(:capture3).with(/bundle why transitivebox/).and_return([bundle_why, "", Status.new(0)])
      analyzer.get_versions(nil)
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

    it "should returns expected data for transitive" do
      do_compare(
        result: subject[0]["transitivebox"],
        owner: ":self_serve",
        current_version: "5.0.3.5",
        latest_version: "7.0.2.2",
        major: 2,
        minor: 0,
        patch: 0,
        age: 1.0
      )
    end

    it "should calculate expected meta_data" do
      expect(subject[1].total_releases).to eq(4)
    end
  end
end
