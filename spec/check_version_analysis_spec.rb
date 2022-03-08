RSpec.describe LibraryVersionAnalysis::CheckVersionStatus do
  let(:expected_results){
    {
      "packwerk": LibraryVersionAnalysis::Versionline.new(owner: "unspecified", current_version: "1.0.3", current_version_date: "2018-01-25", latest_version: "1.1.0", latest_version_date: "2020-11-12", releases_behind: nil, major: 0, minor: 50, patch: 0, age: 2.8),
      "aasm": LibraryVersionAnalysis::Versionline.new(owner: ":core", current_version: "4.1.1", current_version_date: "2020-08-11", latest_version: "5.2.0", latest_version_date: "2021-05-02", releases_behind: nil, major: 1, minor: 0, patch: 0, age: 0.7),
      "actioncable": LibraryVersionAnalysis::Versionline.new(owner: ":api_platform", current_version: "6.0.3.5", current_version_date: "2021-02-10", latest_version: "7.0.2.2", latest_version_date: "2022-02-11", releases_behind: nil, major: 1, minor: 0, patch: 0, age: 1.0),
      "transitivebox": LibraryVersionAnalysis::Versionline.new(owner: ":self_serve", current_version: "5.0.3.5", current_version_date: "2021-02-10", latest_version: "7.0.2.2", latest_version_date: "2022-02-11", releases_behind: nil, major: 2, minor: 0, patch: 0, age: 1.0),
      "actionmailbox": LibraryVersionAnalysis::Versionline.new(owner: "unspecified", current_version: nil, current_version_date: nil, latest_version: nil, latest_version_date: nil, releases_behind: nil, major: 4, minor: 0, patch: 0, age: nil),
      "actionmailer": LibraryVersionAnalysis::Versionline.new(owner: "unspecified", current_version: nil, current_version_date: nil, latest_version: nil, latest_version_date: nil, releases_behind: nil, major: 1, minor: 0, patch: 0, age: nil),
      "actionpack": LibraryVersionAnalysis::Versionline.new(owner: ":api_platform", current_version: nil, current_version_date: nil, latest_version: nil, latest_version_date: nil, releases_behind: nil, major: 2, minor: 0, patch: 0, age: nil),
      "t2": LibraryVersionAnalysis::Versionline.new(owner: "unspecified", current_version: nil, current_version_date: nil, latest_version: nil, latest_version_date: nil, releases_behind: nil, major: 0, minor: 1, patch: 0, age: nil),
      "t3": LibraryVersionAnalysis::Versionline.new(owner: ":api_platform", current_version: nil, current_version_date: nil, latest_version: nil, latest_version_date: nil, releases_behind: nil, major: 0, minor: 0, patch: 1, age: nil),
    }
  }
  let(:expected_meta_data){
    expected = LibraryVersionAnalysis::MetaData.new
    expected.total_age = 23.3

    return expected
  }

  describe "#get_mode_summary" do
    it "should calculate major summary values for mode" do
      mode = subject.get_mode_summary(expected_results, expected_meta_data)

      expect(mode.one_major).to eq(3)
      expect(mode.two_major).to eq(2)
      expect(mode.three_plus_major).to eq(1)
    end

    it "should calculate minor summary values for mode" do
      mode = subject.get_mode_summary(expected_results, expected_meta_data)

      expect(mode.minor).to eq(2)
    end

    it "should calculate patch summary values for mode" do
      mode = subject.get_mode_summary(expected_results, expected_meta_data)

      expect(mode.patch).to eq(1)
    end

    it "should calculate one_number for mode" do
      mode = subject.get_mode_summary(expected_results, expected_meta_data)

      expect(mode.one_number).to eq(122.5)
    end

    it "should calculate total_release for mode" do
      mode = subject.get_mode_summary(expected_results, expected_meta_data)

      expect(mode.total).to eq(9)
    end

    it "should calculate total_lib_years for mode" do
      mode = subject.get_mode_summary(expected_results, expected_meta_data)

      expect(mode.total_lib_years).to eq(23.3)
    end

    it "should calculate unowned for mode" do
      mode = subject.get_mode_summary(expected_results, expected_meta_data)

      expect(mode.unowned_issues).to eq(3)
    end
  end
end
